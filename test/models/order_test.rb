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
end
