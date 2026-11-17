require "test_helper"
require "minitest/mock"

class Erp::Adapters::MultiWarehouseStockTest < ActiveSupport::TestCase
  setup do
    @org = Organisation.create!(name: "Warehouse sync", currency: "EUR", out_of_stock_strategy: "hide")
    @config = @org.create_erp_configuration!(adapter_type: "firebird", enabled: true, sync_products: true,
      product_sync_mode: "update_only", credentials: { host: "host", database_path: "db", username: "user", password: "pass",
        products_filter: "ARMAZEM IN (1, 41)", field_mappings: { products: { external_id: "REF", sku: "REF", stock_quantity: "STOCK" } } })
    @adapter = @config.adapter
    @product = @org.products.create!(name: "Article", published: true)
    @variant = @product.default_variant
    @variant.update!(sku: "A", external_id: "A", external_source: "firebird", track_stock: true,
      published: true, stock_quantity: 3)
    @rows = [{ "REF" => "A", "STOCK" => 3 }, { "REF" => "A", "STOCK" => -1 }]
  end

  def with_rows
    @adapter.stub(:with_connection, ->(&block) { block.call(:db) }) do
      @adapter.stub(:query_as_hashes, ->(*) { @rows }) do
        @adapter.stub(:each_row_as_hash, ->(*) { @rows.each }) do
          Erp::AdapterRegistry.stub(:build, @adapter) { yield }
        end
      end
    end
  end

  test "all read paths sum signed stock and keep distinct references" do
    @rows.insert(1, { "REF" => "B", "STOCK" => 7 })
    with_rows do
      assert_equal({ "A" => 2, "B" => 7 }, @adapter.fetch_products.to_h { |row| [row[:external_id], row[:stock_quantity]] })
      assert_equal 2, @adapter.fetch_products_by_identifiers(external_ids: ["A"], skus: []).find { |r| r[:external_id] == "A" }[:stock_quantity]
      @rows.sort_by! { |row| row["REF"] }
      assert_equal [2, 7], @adapter.each_product.map { |row| row[:stock_quantity] }
    end
  end

  test "general and individual sync use the total and returning to one warehouse restores availability" do
    with_rows do
      result = Erp::Sync::ProductSyncService.new(organisation: @org).call
      assert result.success?, result.error
      assert_equal 1, result.sync_log.records_processed
      assert_equal 2, @variant.reload.stock_quantity
      assert @product.reload.available?

      repeated = Erp::Sync::ProductSyncService.new(organisation: @org).call
      assert repeated.success?, repeated.error
      assert_empty repeated.sync_log.change_details || []

      @rows.last["STOCK"] = -4
      result = Erp::Sync::SingleProductSyncService.new(product: @product).call
      assert result.success?, result.error
      assert_equal 0, result.sync_log.records_failed
      assert_equal(-1, @variant.reload.stock_quantity)
      assert_not @product.reload.available?

      @adapter.credentials[:products_filter] = "ARMAZEM = 1"
      @rows.pop
      result = Erp::Sync::ProductSyncService.new(organisation: @org).call
      assert result.success?, result.error
      assert_equal 3, @variant.reload.stock_quantity
      assert @variant.available?
      assert @product.reload.available?
      assert_equal 1, result.sync_log.change_details.size
    end
  end

  test "streaming orders by the mapped reference and closes the cursor" do
    cursor = Object.new
    fields = [Struct.new(:name).new("REF"), Struct.new(:name).new("STOCK")]
    values = [["A", 3], ["A", -1], ["B", 0]]
    cursor.define_singleton_method(:fields) { fields }
    cursor.define_singleton_method(:fetch) { values.shift }
    closed = false
    cursor.define_singleton_method(:close) { closed = true }
    db = Object.new
    sql = nil
    db.define_singleton_method(:execute) { |query| sql = query; cursor }

    @adapter.stub(:with_connection, ->(&block) { block.call(db) }) do
      assert_equal [2, 0], @adapter.each_product.map { |row| row[:stock_quantity] }
    end
    assert_equal "SELECT * FROM PRODUCTS WHERE ARMAZEM IN (1, 41) ORDER BY REF", sql
    assert closed
  end

  test "invalid stock skips the whole reference logs the error and continues" do
    other = @org.products.create!(name: "Other")
    other.default_variant.update!(sku: "B", external_id: "B", external_source: "firebird", stock_quantity: 1)
    before_variant = @variant.reload.attributes
    before_product = @product.reload.attributes
    [nil, "", "invalid"].product([0, 1]).each do |value, position|
      @rows = [{ "REF" => "A", "STOCK" => 3 }, { "REF" => "A", "STOCK" => -1 }, { "REF" => "B", "STOCK" => 7 }]
      @rows[position]["STOCK"] = value
      with_rows do
        result = Erp::Sync::ProductSyncService.new(organisation: @org).call
        assert result.success?, result.error
        assert_equal 1, result.sync_log.records_failed
        assert_equal 2, result.sync_log.records_processed
        assert_equal before_variant, @variant.reload.attributes
        assert_equal before_product, @product.reload.attributes
        assert_equal 7, other.default_variant.reload.stock_quantity
        error = result.sync_log.reload.error_details.sole
        assert_equal "A", error["record"]
        assert_includes error["error"], "Invalid or missing ERP stock"
        assert_includes error["error"], "STOCK"
      end
    end
  end

  test "individual sync logs invalid stock without changing reference data or hiding valid variants" do
    @product.update!(has_variants: true)
    @variant.reload.update!(is_default: false, sku: "A", external_id: "A", external_source: "firebird",
      track_stock: true, stock_quantity: 3, published: true)
    other = @product.product_variants.create!(name: "Other", sku: "B", external_id: "B", external_source: "firebird",
      is_default: false, track_stock: true, published: true, stock_quantity: 1)
    @rows.last["STOCK"] = nil
    @rows << { "REF" => "B", "STOCK" => 7 }
    with_rows do
      result = Erp::Sync::SingleProductSyncService.new(product: @product).call
      assert result.success?, result.error
      assert_equal 1, result.sync_log.records_failed
      assert_equal 2, result.sync_log.records_processed
      assert_equal 3, @variant.reload.stock_quantity
      assert @variant.published?
      assert_equal 7, other.reload.stock_quantity
      assert_includes @variant.sync_error, "Invalid or missing ERP stock for A"
      assert_includes result.sync_log.reload.error_details.sole["error"], "previous stock preserved"
    end
  end

  test "Nodal managed stock remains untouched" do
    @variant.update!(stock_source: "nodal", stock_quantity: 19)
    with_rows do
      assert Erp::Sync::SingleProductSyncService.new(product: @product).call.success?
      assert_equal 19, @variant.reload.stock_quantity
    end
  end
end
