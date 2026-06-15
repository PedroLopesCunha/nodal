require "test_helper"

class StockRulesServiceTest < ActiveSupport::TestCase
  setup do
    @organisation = Organisation.create!(
      name: "Test Organisation",
      slug: "test-org-#{SecureRandom.hex(4)}",
      currency: "EUR",
      tax_rate: 0.23,
      out_of_stock_strategy: "hide"
    )
    @service = StockRulesService.new(@organisation)
  end

  def simple_product(published: true, available: true)
    Product.create!(
      organisation: @organisation,
      name: "Product #{SecureRandom.hex(4)}",
      slug: "product-#{SecureRandom.hex(4)}",
      unit_price: 1000,
      published: published,
      available: available
    )
  end

  test "non-tracked variant is forced available even when stuck at false" do
    product = simple_product(available: false)
    variant = product.default_variant
    variant.update_columns(track_stock: false, available: false, published: true)

    @service.apply_to_variant(variant)

    assert variant.reload.available, "non-tracked variant must become available"
    assert product.reload.available, "product must roll up to available"
  end

  test "non-tracked variant that is already available stays available" do
    product = simple_product(available: true)
    variant = product.default_variant
    variant.update_columns(track_stock: false, available: true, published: true)

    @service.apply_to_variant(variant)

    assert variant.reload.available
  end

  test "tracked track_only variant stays available with zero stock" do
    product = simple_product(available: false)
    variant = product.default_variant
    variant.update_columns(track_stock: true, stock_policy: "track_only",
                           stock_quantity: 0, available: false, published: true)

    @service.apply_to_variant(variant)

    assert variant.reload.available
    assert product.reload.available
  end

  test "tracked hide variant reflects actual stock" do
    product = simple_product(available: true)
    variant = product.default_variant
    variant.update_columns(track_stock: true, stock_policy: "hide",
                           stock_quantity: 0, available: true, published: true)

    @service.apply_to_variant(variant)

    refute variant.reload.available, "out-of-stock tracked variant must become unavailable"

    variant.update_columns(stock_quantity: 5)
    @service.apply_to_variant(variant)

    assert variant.reload.available, "in-stock tracked variant must become available"
  end
end
