require "test_helper"

class ProductTest < ActiveSupport::TestCase
  def setup
    @org = Organisation.create!(name: "Grid Test Org")
    @product = Product.create!(organisation: @org, name: "Widget", unit_price: 1000, published: true)
  end

  test "defaults add_to_cart_mode to default" do
    assert_equal "default", @product.add_to_cart_mode
  end

  test "rejects an invalid add_to_cart_mode" do
    @product.add_to_cart_mode = "weird"
    assert_not @product.valid?
    assert_includes @product.errors[:add_to_cart_mode], "is not included in the list"
  end

  test "grid_add_to_cart? is false for simple products even in grid mode" do
    @product.update!(add_to_cart_mode: "grid")
    assert_not @product.grid_add_to_cart?
  end

  test "grid_add_to_cart? is true when mode is grid and product has variants" do
    @product.update!(has_variants: true, add_to_cart_mode: "grid")
    assert @product.grid_add_to_cart?
  end

  test "grid_add_to_cart? is false in default mode" do
    @product.update!(has_variants: true, add_to_cart_mode: "default")
    assert_not @product.grid_add_to_cart?
  end

  test "converting variable -> simple promotes the default variant price/sku to the product" do
    product = Product.create!(organisation: @org, name: "Convertible", unit_price: nil,
                              published: true, has_variants: true)
    # Variable product: price lives on the variant, product.unit_price stays nil
    product.default_variant.update_columns(unit_price_cents: 1800, sku: "CONV-1")
    assert_nil product.reload.unit_price

    product.update!(has_variants: false)

    assert_equal 1800, product.reload.unit_price, "product price must be promoted from the variant"
    assert_equal "CONV-1", product.sku
  end

  test "converting variable -> simple does not wipe an existing variant price" do
    product = Product.create!(organisation: @org, name: "Convertible2", unit_price: nil,
                              published: true, has_variants: true)
    product.default_variant.update_columns(unit_price_cents: 2500, sku: "CONV-2")

    product.update!(has_variants: false)

    assert_equal 2500, product.reload.default_variant.unit_price_cents
    assert_equal 2500, product.unit_price
  end
end
