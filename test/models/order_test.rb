require "test_helper"

class OrderTest < ActiveSupport::TestCase
  def setup
    @org = Organisation.create!(name: "Order Refresh Org")
    @customer = Customer.create!(organisation: @org, company_name: "Acme", contact_name: "Jane", active: true)
    @customer_user = CustomerUser.create!(organisation: @org, customer: @customer,
      email: "jane@acme.test", password: "password123", password_confirmation: "password123",
      contact_name: "Jane", active: true)
    @product = Product.create!(organisation: @org, name: "Widget", unit_price: 1000, published: true)
    @order = Order.create!(customer: @customer, customer_user: @customer_user, organisation: @org)
  end

  test "refresh_cart! persists changed line items and reports the deltas" do
    item = @order.order_items.create!(product: @product, quantity: 1)
    @product.default_variant.update!(unit_price_cents: 1500)
    @order.reload

    changes = @order.refresh_cart!

    assert_equal [item.id], changes[:price_changed]
    assert_equal 1500, item.reload.unit_price
  end

  test "refresh_cart! is a no-op for placed orders" do
    item = @order.order_items.create!(product: @product, quantity: 1)
    @order.update!(placed_at: Time.current)
    @product.default_variant.update!(unit_price_cents: 1500)
    @order.reload

    changes = @order.refresh_cart!

    assert_equal [], changes[:price_changed]
    assert_equal 1000, item.reload.unit_price
  end

  test "finalize_checkout! snapshots fresh line pricing before placing" do
    item = @order.order_items.create!(product: @product, quantity: 1)
    @product.default_variant.update!(unit_price_cents: 2000)
    @order.reload
    @order.terms_accepted_at = Time.current

    @order.finalize_checkout!

    assert @order.placed?
    assert_equal 2000, item.reload.unit_price
  end

  test "refresh_cart! removes out-of-stock items under the remove policy" do
    @org.update!(cart_stock_policy: "remove")
    item = @order.order_items.create!(product: @product, quantity: 1)
    @product.default_variant.update!(track_stock: true, stock_quantity: 0, stock_policy: "show_badge")
    @order.reload

    changes = @order.refresh_cart!

    assert_equal 1, changes[:removed].size
    assert_not OrderItem.exists?(item.id)
  end

  test "refresh_cart! keeps and records out-of-stock items under the warn policy" do
    item = @order.order_items.create!(product: @product, quantity: 1)
    @product.default_variant.update!(track_stock: true, stock_quantity: 0, stock_policy: "show_badge")
    @order.reload

    changes = @order.refresh_cart!

    assert OrderItem.exists?(item.id)
    assert_equal 1, changes[:out_of_stock].size
  end

  test "refresh_cart! caps quantity to available stock under the cap policy" do
    @org.update!(cart_qty_overflow_policy: "cap")
    item = @order.order_items.create!(product: @product, quantity: 5)
    @product.default_variant.update!(track_stock: true, stock_quantity: 2)
    @order.reload

    changes = @order.refresh_cart!

    assert_equal 2, item.reload.quantity
    assert_equal 2, changes[:capped].first[:to]
  end

  test "refresh_cart! warns on qty overflow without changing quantity by default" do
    item = @order.order_items.create!(product: @product, quantity: 5)
    @product.default_variant.update!(track_stock: true, stock_quantity: 2)
    @order.reload

    changes = @order.refresh_cart!

    assert_equal 5, item.reload.quantity
    assert_equal 2, changes[:qty_overflow].first[:available]
  end
end
