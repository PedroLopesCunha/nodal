require "test_helper"

class LocalStockTest < ActiveSupport::TestCase
  setup do
    @org = Organisation.create!(name: "Local Stock", out_of_stock_strategy: "deactivate", checkout_stock_policy: "block", cart_stock_policy: "warn", cart_qty_overflow_policy: "warn")
    @customer = Customer.create!(organisation: @org, company_name: "Buyer", contact_name: "Ana", active: true)
    @user = CustomerUser.create!(organisation: @org, customer: @customer, email: "stock@example.test",
      password: "password123", password_confirmation: "password123", contact_name: "Ana", active: true)
    @product = Product.create!(organisation: @org, name: "Blue", unit_price: 1000, published: true)
    @variant = @product.default_variant
    @variant.update!(stock_source: "nodal", stock_quantity: 10)
    @order = Order.create!(organisation: @org, customer: @customer, customer_user: @user)
    @item = @order.order_items.create!(product: @product, quantity: 3)
  end

  test "cart does not consume and placement consumes once" do
    assert_equal 10, @variant.reload.stock_quantity
    @order.place!
    assert_equal 7, @variant.reload.stock_quantity
    assert_equal 3, @item.reload.local_stock_consumed
    @order.place!
    @order.update!(notes: "Unchanged lines")
    assert_equal 7, @variant.reload.stock_quantity
  end

  test "ERP lines remain unchanged in a mixed order" do
    other = Product.create!(organisation: @org, name: "ERP", unit_price: 500, published: true)
    other.default_variant.update!(stock_quantity: 20)
    @order.order_items.create!(product: other, quantity: 4)
    @order.place!
    assert_equal 7, @variant.reload.stock_quantity
    assert_equal 20, other.default_variant.reload.stock_quantity
  end

  test "BO quantity changes and removal reconcile only the difference" do
    @order.place!
    @order.update!(order_items_attributes: [{ id: @item.id, quantity: 5 }])
    assert_equal 5, @variant.reload.stock_quantity
    @order.update!(order_items_attributes: [{ id: @item.id, quantity: 2 }])
    assert_equal 8, @variant.reload.stock_quantity
    @order.update!(order_items_attributes: [{ id: @item.id, _destroy: "1" }])
    assert_equal 10, @variant.reload.stock_quantity
  end

  test "BO creates a placed order and consumes its nested lines" do
    order = Order.create!(organisation: @org, customer: @customer, customer_user: @user, placed_at: Time.current,
      order_items_attributes: [{ product_variant_id: @variant.id, quantity: 2 }])
    assert_equal 8, @variant.reload.stock_quantity
    assert_equal 2, order.order_items.first.local_stock_consumed
  end

  test "insufficient stock rolls back BO edits" do
    @order.place!
    assert_not @order.update(order_items_attributes: [{ id: @item.id, quantity: 11 }])
    assert_equal 3, @item.reload.quantity
    assert_equal 7, @variant.reload.stock_quantity
  end

  test "removing a legacy line does not invent stock" do
    @order.update_column(:placed_at, Time.current)
    @order.update!(order_items_attributes: [{ id: @item.id, _destroy: "1" }])
    assert_equal 10, @variant.reload.stock_quantity
  end

  test "manual adjustment is the new available quantity" do
    @order.place!
    @variant.update!(stock_quantity: 20)
    @order.update!(order_items_attributes: [{ id: @item.id, quantity: 2 }])
    assert_equal 21, @variant.reload.stock_quantity
  end

  test "destroy restores only in-process orders" do
    @order.place!
    @order.destroy!
    assert_equal 10, @variant.reload.stock_quantity
  end

  test "destroying a completed order does not restore stock" do
    @order.place!
    @order.update!(status: "completed")
    @order.destroy!
    assert_equal 7, @variant.reload.stock_quantity
  end

  test "a second cart cannot buy the units consumed by the first" do
    @order.update!(order_items_attributes: [{ id: @item.id, quantity: 10 }])
    other = Order.create!(organisation: @org, customer: @customer, customer_user: @user, terms_accepted_at: Time.current)
    other.order_items.create!(product: @product, quantity: 1)
    other.order_items.includes(:product_variant).load
    @order.place!
    assert_not @variant.reload.available?
    assert_not @product.reload.available?
    assert_raises(ActiveRecord::RecordInvalid) { other.finalize_checkout! }
    assert_not other.reload.placed?
    assert_equal 0, @variant.reload.stock_quantity
  end

  test "checkout allows negative stock only under its existing override policy" do
    @org.update!(checkout_stock_policy: "allow")
    @order.update!(order_items_attributes: [{ id: @item.id, quantity: 12 }])
    @order.terms_accepted_at = Time.current
    @order.finalize_checkout!
    assert_equal(-2, @variant.reload.stock_quantity)
    assert_raises(ActiveRecord::RecordInvalid) { @order.finalize_checkout! }
    assert_equal(-2, @variant.reload.stock_quantity)
  end

  test "ERP sync never overwrites a Nodal quantity" do
    service = Erp::Sync::ProductSyncService.allocate
    service.send(:update_stock, @variant, stock_quantity: 99)
    assert_equal 10, @variant.stock_quantity
    @variant.stock_source = "erp"
    service.send(:update_stock, @variant, stock_quantity: 99)
    assert_equal 99, @variant.stock_quantity
  end

  test "simple products edit the default variant inventory" do
    @product.update!(inventory_attributes: { stock_source: "nodal", stock_quantity: 4, stock_policy: "hide" })
    assert_equal 4, @variant.reload.stock_quantity
    assert_equal "hide", @variant.stock_policy
  end

  test "simple product creation applies its initial inventory" do
    product = Product.create!(organisation: @org, name: "New", unit_price: 1000,
      inventory_attributes: { stock_source: "nodal", stock_quantity: 8 })
    assert_equal "nodal", product.default_variant.stock_source
    assert_equal 8, product.default_variant.stock_quantity
  end
  test "changing a placed line to an ERP variant returns only its original Nodal stock" do
    other = Product.create!(organisation: @org, name: "ERP replacement", unit_price: 500, published: true)
    other.default_variant.update!(stock_quantity: 20)
    @order.place!
    @order.update!(order_items_attributes: [{ id: @item.id, product_variant_id: other.default_variant.id, quantity: 4 }])
    assert_equal 10, @variant.reload.stock_quantity
    assert_equal 20, other.default_variant.reload.stock_quantity
    assert_equal 0, @item.reload.local_stock_consumed
    @order.destroy!
    assert_equal 20, other.default_variant.reload.stock_quantity
  end

  test "insufficient stock on a later line rolls back all movements" do
    other = Product.create!(organisation: @org, name: "Scarce", unit_price: 500, published: true)
    other.default_variant.update!(stock_source: "nodal", stock_quantity: 2)
    @order.order_items.create!(product: other, quantity: 3)
    assert_raises(ActiveRecord::RecordInvalid) { @order.place! }
    assert_not @order.reload.placed?
    assert_equal 10, @variant.reload.stock_quantity
    assert_equal 2, other.default_variant.reload.stock_quantity
    assert_equal 0, @order.order_items.sum(:local_stock_consumed)
  end

  test "untracked Nodal variants do not consume stock" do
    @variant.update!(track_stock: false)
    @order.place!
    assert_equal 10, @variant.reload.stock_quantity
    assert_equal 0, @item.reload.local_stock_consumed
  end

  test "edits after switching to ERP do not move the ERP quantity" do
    @order.place!
    @variant.update!(stock_source: "erp", stock_quantity: 50)
    @order.update!(order_items_attributes: [{ id: @item.id, _destroy: "1" }])
    assert_equal 50, @variant.reload.stock_quantity
  end

  test "stale BO instances reconcile against persisted consumption" do
    @order.place!
    stale = Order.find(@order.id)
    stale.order_items.load
    @order.update!(order_items_attributes: [{ id: @item.id, quantity: 5 }])
    stale.update!(order_items_attributes: [{ id: @item.id, quantity: 4 }])
    assert_equal 6, @variant.reload.stock_quantity
    assert_equal 4, @item.reload.local_stock_consumed
    stale.update!(order_items_attributes: [{ id: @item.id, _destroy: "1" }])
    assert_equal 10, @variant.reload.stock_quantity
  end

  test "orders cannot consume stock belonging to another organisation" do
    other_org = Organisation.create!(name: "Other Stock Owner")
    other = Product.create!(organisation: other_org, name: "Private", unit_price: 500, published: true)
    other.default_variant.update!(stock_source: "nodal", stock_quantity: 5)
    assert_not @order.update(order_items_attributes: [{ product_variant_id: other.default_variant.id, quantity: 1, price: "5.00" }])
    assert_equal 5, other.default_variant.reload.stock_quantity
  end

end
