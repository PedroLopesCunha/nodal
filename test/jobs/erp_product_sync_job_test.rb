require "test_helper"
require "minitest/mock"

class ErpProductSyncJobTest < ActiveJob::TestCase
  Adapter = Struct.new(:rows) do
    def fetch_products_by_identifiers(**)
      rows
    end
  end

  setup do
    @org = Organisation.create!(name: "ERP Job Org", currency: "EUR")
    member = Member.create!(email: "erp-task@example.com", password: "password123", first_name: "Ana", last_name: "Admin")
    @org.create_erp_configuration!(adapter_type: "custom_api", enabled: true, sync_products: true,
      product_sync_mode: "update_only", credentials: { base_url: "https://erp.example.test", api_key: "test" })
    @product = @org.products.create!(name: "Product", sku: "ONE", unit_price: 1000)
    @task = @org.background_tasks.create!(member: member, task_type: "erp_product_sync", result: { product_id: @product.id })
  end

  test "task completes with progress and the product return link" do
    adapter = Adapter.new([{ external_id: "erp-one", sku: "ONE", unit_price_cents: 2000 }])
    Erp::AdapterRegistry.stub(:build, adapter) { ErpProductSyncJob.perform_now(@task.id, product_id: @product.id) }
    assert @task.reload.completed?
    assert_equal 1, @task.progress
    assert_equal 1, @task.total
    assert_equal @product.id, @task.result["product_id"]
    assert_equal 2000, @product.reload.unit_price
  end

  test "missing ERP item marks the task failed with a readable error" do
    Erp::AdapterRegistry.stub(:build, Adapter.new([])) do
      assert_raises(Erp::ApiError) { ErpProductSyncJob.perform_now(@task.id, product_id: @product.id) }
    end
    assert @task.reload.failed?
    assert_includes @task.error_message, "not found in ERP"
  end

  test "cancelled tasks do not contact ERP" do
    @task.update!(status: :cancelled)
    Erp::Sync::SingleProductSyncService.stub(:new, ->(**) { flunk "ERP should not be contacted" }) do
      ErpProductSyncJob.perform_now(@task.id, product_id: @product.id)
    end
    assert @task.reload.cancelled?
    assert_equal 1000, @product.reload.unit_price
  end
  test "unreadable credentials report a configuration error through the task" do
    Erp::Sync::SingleProductSyncService.stub(:new, ->(**) { raise ActiveRecord::Encryption::Errors::Decryption }) do
      assert_raises(Erp::ConfigurationError) { ErpProductSyncJob.perform_now(@task.id, product_id: @product.id) }
    end
    assert @task.reload.failed?
    assert_equal I18n.t('bo.products.erp_sync.invalid_credentials'), @task.error_message
  end

end
