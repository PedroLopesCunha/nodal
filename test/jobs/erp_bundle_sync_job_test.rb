require "test_helper"
require "minitest/mock"

class ErpBundleSyncJobTest < ActiveJob::TestCase
  Adapter = Struct.new(:rows) do
    def fetch_products_by_identifiers(**)
      rows
    end
  end

  setup do
    @org = Organisation.create!(name: "Bundle ERP", currency: "EUR", out_of_stock_strategy: "hide")
    member = Member.create!(email: "bundle-sync@example.com", password: "password123", first_name: "Ana", last_name: "Admin")
    @org.create_erp_configuration!(adapter_type: "custom_api", enabled: true, sync_products: true,
      product_sync_mode: "update_only", credentials: { base_url: "https://erp.example.test", api_key: "test" })
    @products = %w[ONE TWO].map { |sku| @org.products.create!(name: sku, sku: sku, published: true, unit_price: 1000) }
    @products.each { |p| p.default_variant.update!(track_stock: true, stock_quantity: 10) }
    @bundle = @org.products.create!(name: "Set", bundle: true, published: true, unit_price: 1500,
      bundle_components_attributes: @products.map { |p| { product_variant_id: p.default_variant.id, quantity: 2 } })
    @task = @org.background_tasks.create!(member: member, task_type: "erp_product_sync")
  end

  test "syncs components and refreshes capacity without changing the bundle price" do
    rows = %w[ONE TWO].map { |sku| { external_id: sku, sku: sku, unit_price_cents: 2000, stock_quantity: 6 } }
    Erp::AdapterRegistry.stub(:build, Adapter.new(rows)) { ErpBundleSyncJob.perform_now(@task.id, product_id: @bundle.id) }
    assert @task.reload.completed?
    assert_equal 2, @task.progress
    assert_equal 2, @task.total
    assert_equal [2000, 2000], @products.map { |p| p.reload.unit_price }
    assert_equal 1500, @bundle.reload.unit_price
    assert_equal 3, @bundle.bundle_capacity
  end

  test "continues to other products and reports failed references" do
    rows = [{ external_id: "TWO", sku: "TWO", unit_price_cents: 2500, stock_quantity: 4 }]
    Erp::AdapterRegistry.stub(:build, Adapter.new(rows)) do
      assert_raises(Erp::ApiError) { ErpBundleSyncJob.perform_now(@task.id, product_id: @bundle.id) }
    end
    assert @task.reload.failed?
    assert @task.result["errors"].any?
    assert_equal 1000, @products.first.reload.unit_price
    assert_equal 2500, @products.last.reload.unit_price
    assert_equal 1500, @bundle.reload.unit_price
  end
end
