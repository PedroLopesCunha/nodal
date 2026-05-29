require "test_helper"

class OrderItemTest < ActiveSupport::TestCase
  def setup
    @org = Organisation.create!(name: "Refresh Test Org")
    @customer = Customer.create!(organisation: @org, company_name: "Acme", contact_name: "Jane", active: true)
    @customer_user = CustomerUser.create!(organisation: @org, customer: @customer,
      email: "jane@acme.test", password: "password123", password_confirmation: "password123",
      contact_name: "Jane", active: true)
    @product = Product.create!(organisation: @org, name: "Widget", unit_price: 1000, published: true)
    @order = Order.create!(customer: @customer, customer_user: @customer_user, organisation: @org)
  end

  test "refresh_pricing! drops an expired discount to zero" do
    discount = ProductDiscount.create!(organisation: @org, product: @product,
      discount_type: "percentage", discount_value: 0.10, min_quantity: 1, active: true)
    item = @order.order_items.create!(product: @product, quantity: 1)
    assert_equal 0.10, item.discount_percentage.to_f.round(4)

    discount.update!(valid_until: Date.yesterday)
    item.reload
    changes = item.refresh_pricing!

    assert_equal 0.0, item.discount_percentage.to_f
    assert changes.key?(:discount_percentage)
  end

  test "refresh_pricing! picks up a variant price change" do
    item = @order.order_items.create!(product: @product, quantity: 1)
    assert_equal 1000, item.unit_price

    @product.default_variant.update!(unit_price_cents: 1500)
    item.reload
    changes = item.refresh_pricing!

    assert_equal 1500, item.unit_price
    assert_equal [1000, 1500], changes[:unit_price]
  end

  test "refresh_pricing! applies a customer tier discount added after add-to-cart" do
    item = @order.order_items.create!(product: @product, quantity: 1)
    assert_equal 0.0, item.discount_percentage.to_f

    CustomerDiscount.create!(organisation: @org, customer: @customer,
      discount_type: "percentage", discount_value: 0.05, active: true)
    item.reload
    changes = item.refresh_pricing!

    assert_equal 0.05, item.discount_percentage.to_f.round(4)
    assert changes.key?(:discount_percentage)
  end

  test "refresh_pricing! returns empty hash when nothing changed" do
    item = @order.order_items.create!(product: @product, quantity: 1)
    item.reload
    assert_equal({}, item.refresh_pricing!)
  end

  test "refresh_pricing! is a no-op once the order is placed" do
    item = @order.order_items.create!(product: @product, quantity: 1)
    @order.update!(placed_at: Time.current)
    @product.default_variant.update!(unit_price_cents: 9999)
    item.reload

    assert_equal({}, item.refresh_pricing!)
    assert_equal 1000, item.unit_price
  end

  test "stock_status is purchasable when quantity fits the tracked stock" do
    @product.default_variant.update!(track_stock: true, stock_quantity: 10)
    item = @order.order_items.create!(product: @product, quantity: 3)
    item.reload
    assert_equal :purchasable, item.stock_status
  end

  test "stock_status flags qty_overflow when quantity exceeds tracked stock" do
    item = @order.order_items.create!(product: @product, quantity: 5)
    @product.default_variant.update!(track_stock: true, stock_quantity: 2)
    item.reload
    assert_equal :qty_overflow, item.stock_status
  end

  test "stock_status is out_of_stock when a tracked variant hits zero" do
    item = @order.order_items.create!(product: @product, quantity: 1)
    @product.default_variant.update!(track_stock: true, stock_quantity: 0, stock_policy: "show_badge")
    item.reload
    assert_equal :out_of_stock, item.stock_status
  end

  test "stock_status is variant_unpublished when the variant is unpublished" do
    item = @order.order_items.create!(product: @product, quantity: 1)
    @product.default_variant.update!(published: false)
    item.reload
    assert_equal :variant_unpublished, item.stock_status
  end
end
