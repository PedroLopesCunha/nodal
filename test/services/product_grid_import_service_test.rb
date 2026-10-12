require "test_helper"

class ProductGridImportServiceTest < ActiveSupport::TestCase
  setup do
    @org = Organisation.create!(name: "Grid grouping", currency: "EUR")
    @source = @org.products.create!(name: "Original", sku: "UNIT", unit_price: 10900)
    @unit = @source.default_variant
    @unit.update!(stock_source: "nodal", stock_quantity: 2, external_id: "UNIT")
    @rows = [
      { "tipo" => "variable", "sku" => "GROUP", "nome" => "Group" },
      { "tipo" => "variation", "sku" => "UNIT", "sku_pai" => "GROUP", "nome" => "Unit", "preco" => "118" }
    ]
  end

  test "grouping reuses the unit and retires its empty original product" do
    result = ProductGridImportService.new(organisation: @org, rows: @rows).call
    assert_empty result.errors
    parent = @org.products.find_by!(sku: "GROUP")
    assert_equal parent.id, @unit.reload.product_id
    assert_not @unit.is_default?
    assert_equal 11800, @unit.unit_price_cents
    assert_equal 2, @unit.stock_quantity
    assert_equal "nodal", @unit.stock_source
    assert_equal "UNIT", @unit.external_id
    assert_empty @source.product_variants.reload
    assert_not @source.reload.published?
    assert_equal [parent.default_variant.id], parent.product_variants.default.ids
  end

  test "a later import error rolls back the move and retirement" do
    @rows << { "tipo" => "variation", "sku" => "OTHER", "sku_pai" => "MISSING", "nome" => "Other" }
    result = ProductGridImportService.new(organisation: @org, rows: @rows).call
    assert_not_empty result.errors
    assert_equal @source.id, @unit.reload.product_id
    assert @unit.is_default?
    assert @source.reload.published?
    assert_nil @org.products.find_by(sku: "GROUP")
  end

  test "blank SKU creates a new unit instead of reusing the previous row" do
    @rows << { "tipo" => "variation", "sku_pai" => "GROUP", "nome" => "No SKU" }
    result = ProductGridImportService.new(organisation: @org, rows: @rows).call
    assert_empty result.errors
    parent = @org.products.find_by!(sku: "GROUP")
    assert_equal 2, parent.product_variants.where(is_default: false).count
    assert_equal "Unit", @unit.reload.name
  end

  test "a simple parent is rejected without moving its unit" do
    @rows = [@rows.last.merge("sku_pai" => "UNIT")]
    result = ProductGridImportService.new(organisation: @org, rows: @rows).call
    assert_not_empty result.errors
    assert @unit.reload.is_default?
    assert @source.reload.published?
  end
end
