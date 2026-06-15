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
    @product.default_variant.update!(track_stock: true, stock_quantity: 2, stock_policy: "show_badge")
    @order.reload

    changes = @order.refresh_cart!

    assert_equal 2, item.reload.quantity
    assert_equal 2, changes[:capped].first[:to]
  end

  test "refresh_cart! warns on qty overflow without changing quantity by default" do
    item = @order.order_items.create!(product: @product, quantity: 5)
    @product.default_variant.update!(track_stock: true, stock_quantity: 2, stock_policy: "show_badge")
    @order.reload

    changes = @order.refresh_cart!

    assert_equal 5, item.reload.quantity
    assert_equal 2, changes[:qty_overflow].first[:available]
  end

  test "finalize_checkout! blocks placing with out-of-stock items under block policy" do
    @org.update!(checkout_stock_policy: "block")
    @order.order_items.create!(product: @product, quantity: 1)
    @product.default_variant.update!(track_stock: true, stock_quantity: 0, stock_policy: "show_badge")
    @order.reload
    @order.terms_accepted_at = Time.current

    assert_raises(ActiveRecord::RecordInvalid) { @order.finalize_checkout! }
    assert_not @order.reload.placed?
  end

  test "finalize_checkout! requires confirmation for out-of-stock items under warn policy" do
    # default checkout_stock_policy is "warn"
    @order.order_items.create!(product: @product, quantity: 1)
    @product.default_variant.update!(track_stock: true, stock_quantity: 0, stock_policy: "show_badge")
    @order.reload
    @order.terms_accepted_at = Time.current

    assert_raises(ActiveRecord::RecordInvalid) { @order.finalize_checkout! }
    assert_not @order.reload.placed?
  end

  test "finalize_checkout! places under warn policy once confirmed" do
    @order.order_items.create!(product: @product, quantity: 1)
    @product.default_variant.update!(track_stock: true, stock_quantity: 0, stock_policy: "show_badge")
    @order.reload
    @order.terms_accepted_at = Time.current
    @order.confirmed_stock_warnings = "1"

    @order.finalize_checkout!

    assert @order.placed?
  end

  test "finalize_checkout! places out-of-stock items under allow policy" do
    @org.update!(checkout_stock_policy: "allow")
    @order.order_items.create!(product: @product, quantity: 1)
    @product.default_variant.update!(track_stock: true, stock_quantity: 0, stock_policy: "show_badge")
    @order.reload
    @order.terms_accepted_at = Time.current

    @order.finalize_checkout!

    assert @order.placed?
  end

  test "refresh_cart! flags a pending pricing change under the confirm policy" do
    @org.update!(cart_price_change_policy: "confirm")
    @order.order_items.create!(product: @product, quantity: 1)
    @product.default_variant.update!(unit_price_cents: 1500)
    @order.reload

    @order.refresh_cart!

    assert @order.reload.pricing_change_pending?
  end

  test "refresh_cart! does not flag a pending pricing change under notify" do
    # default cart_price_change_policy is "notify"
    @order.order_items.create!(product: @product, quantity: 1)
    @product.default_variant.update!(unit_price_cents: 1500)
    @order.reload

    @order.refresh_cart!

    assert_not @order.reload.pricing_change_pending?
  end

  test "acknowledge_pricing_change! clears the pending flag" do
    @order.update_column(:pricing_changed_at, Time.current)
    @order.acknowledge_pricing_change!
    assert_not @order.reload.pricing_change_pending?
  end

  test "finalize_checkout! blocks under confirm until the pricing change is acknowledged" do
    @org.update!(cart_price_change_policy: "confirm")
    @order.order_items.create!(product: @product, quantity: 1)
    @product.default_variant.update!(unit_price_cents: 1500)
    @order.reload
    @order.terms_accepted_at = Time.current

    assert_raises(ActiveRecord::RecordInvalid) { @order.finalize_checkout! }
    assert_not @order.reload.placed?

    @order.acknowledge_pricing_change!
    @order.terms_accepted_at = Time.current
    @order.finalize_checkout!

    assert @order.placed?
  end

  test "finalize_checkout! blocks when a line is below the product minimum" do
    @product.update!(min_quantity: 12)
    item = @order.order_items.create!(product: @product, quantity: 12)
    # Simulate a legacy/grid-built line that dropped below the minimum
    item.update_column(:quantity, 3)
    @order.reload
    @order.terms_accepted_at = Time.current

    assert_raises(ActiveRecord::RecordInvalid) { @order.finalize_checkout! }
    assert_not @order.reload.placed?

    item.update_column(:quantity, 12)
    @order.reload
    @order.terms_accepted_at = Time.current
    @order.finalize_checkout!

    assert @order.placed?
  end
end
