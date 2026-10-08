require "test_helper"
require "minitest/mock"

class Erp::Sync::SingleProductSyncServiceTest < ActiveSupport::TestCase
  FakeAdapter = Struct.new(:rows, :request) do
    def fetch_products_by_identifiers(external_ids:, skus:)
      self.request = { external_ids: external_ids, skus: skus }
      rows
    end
  end

  setup do
    @org = Organisation.create!(name: "Single ERP Org", currency: "EUR")
    @config = @org.create_erp_configuration!(adapter_type: "custom_api", enabled: true, sync_products: true, product_sync_mode: "update_only",
      credentials: { base_url: "https://erp.example.test", api_key: "test" })
    @product = @org.products.create!(name: "Camisa", has_variants: true)
    @base = @product.default_variant
    @variant = @product.product_variants.create!(name: "Azul", sku: "BLUE", unit_price_cents: 1000,
      external_id: "erp-blue", external_source: "custom_api", is_default: false)
    @other = @org.products.create!(name: "Other", unit_price: 1000, sku: "OTHER")
    @adapter = FakeAdapter.new([{ external_id: "erp-blue", sku: "BLUE", unit_price_cents: 2500, stock_quantity: 8 }])
  end

  def sync
    Erp::AdapterRegistry.stub(:build, @adapter) { Erp::Sync::SingleProductSyncService.new(product: @product).call }
  end

  test "updates only the real variants of this product" do
    result = sync
    assert result.success?
    assert_equal 2500, @variant.reload.unit_price_cents
    assert_equal 8, @variant.stock_quantity
    assert @variant.last_synced_at
    assert_nil @base.reload.unit_price_cents
    assert_equal 1000, @other.reload.unit_price
    assert_equal({ external_ids: ["erp-blue"], skus: ["BLUE"] }, @adapter.request)
    assert_equal 1, result.sync_log.records_processed
  end

  test "matches by SKU and preserves Nodal managed stock" do
    @variant.update!(external_id: nil, external_source: nil, stock_source: "nodal", stock_quantity: 19)
    result = sync
    assert result.success?
    assert_equal "erp-blue", @variant.reload.external_id
    assert_equal 19, @variant.stock_quantity
    assert_equal 2500, @variant.unit_price_cents
  end

  test "simple product updates its default variant and product price" do
    @product = @other
    @adapter.rows = [{ external_id: "erp-other", sku: "OTHER", unit_price_cents: 3000 }]
    assert sync.success?
    assert_equal 3000, @other.reload.unit_price
    assert_equal "erp-other", @other.default_variant.external_id
  end

  test "missing ERP record records an error without creating unrelated products" do
    @adapter.rows = []
    assert_no_difference "Product.count" do
      result = sync
      assert_equal 1, result.sync_log.records_failed
    end
    assert_equal 1000, @variant.reload.unit_price_cents
    assert @variant.sync_error.present?
  end

  test "does not run while a general product sync is in progress" do
    ErpSyncLog.start!(organisation: @org, erp_configuration: @config, sync_type: "manual", entity_type: "products")
    result = sync
    assert_not result.success?
    assert_nil @adapter.request
  end
end
