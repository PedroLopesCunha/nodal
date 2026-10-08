require "test_helper"
require "minitest/mock"

class Erp::Adapters::SingleProductLookupTest < ActiveSupport::TestCase
  test "Firebird filters by bound identifiers and keeps the configured product filter" do
    adapter = Erp::Adapters::FirebirdAdapter.new(host: "host", database_path: "db", username: "user", password: "pass",
      products_table: "ARTIGOS", products_filter: "ACTIVO = 1", field_mappings: { products: { external_id: "CODIGO", sku: "REF" } })
    query = nil
    adapter.stub(:with_connection, ->(&block) { block.call(:db) }) do
      adapter.stub(:query_as_hashes, ->(db, sql, *params) { query = [sql, params]; [] }) do
        adapter.fetch_products_by_identifiers(external_ids: ["a'b"], skus: ["BLUE"])
      end
    end
    assert_includes query.first, "(ACTIVO = 1) AND (CODIGO IN (?) OR REF IN (?))"
    assert_equal ["a'b", "BLUE"], query.last
    assert_not_includes query.first, "a'b"
  end

  test "generic API fallback returns only matching records" do
    adapter = Erp::BaseAdapter.new({})
    rows = [{ external_id: "one", sku: "A" }, { external_id: "two", sku: "B" }]
    adapter.stub(:fetch_products, rows) do
      assert_equal [rows.first], adapter.fetch_products_by_identifiers(external_ids: ["one"], skus: [])
    end
  end
end
