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
end
