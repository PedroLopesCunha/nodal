require "test_helper"

class Bo::LocalStockTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @org = Organisation.create!(name: "Stock Forms", currency: "EUR")
    @admin = Member.create!(email: "stock-admin@example.test", password: "password123", first_name: "Ana", last_name: "Admin")
    @org.org_members.create!(member: @admin, role: "owner", active: true)
    sign_in @admin
    @product = @org.products.create!(name: "Widget", unit_price: 1000, published: true)
    @variant = @product.default_variant
    @variant.update!(stock_quantity: 10)
  end

  test "simple product form exposes stock source and read-only ERP quantity" do
    get edit_bo_product_path(org_slug: @org.slug, id: @product.id)
    assert_response :success
    assert_select 'select[name="product[inventory_attributes][stock_source]"]'
    assert_select 'input[name="product[inventory_attributes][stock_quantity]"][readonly]'
  end

  test "simple product form saves Nodal inventory" do
    patch bo_product_path(org_slug: @org.slug, id: @product.id), params: {
      product: { inventory_attributes: { stock_source: "nodal", track_stock: "1", stock_quantity: "6" } }
    }
    assert_response :redirect
    assert_equal "nodal", @variant.reload.stock_source
    assert_equal 6, @variant.stock_quantity
  end

  test "new simple product form renders inventory" do
    get new_bo_product_path(org_slug: @org.slug)
    assert_response :success
    assert_select 'select[name="product[inventory_attributes][stock_source]"]'
  end

  test "variant form saves Nodal stock and ignores manual ERP quantities" do
    patch bo_product_variant_path(org_slug: @org.slug, product_id: @product.id, id: @variant.id), params: {
      product_variant: { stock_source: "nodal", stock_quantity: "5", track_stock: "1" }
    }
    assert_response :redirect
    assert_equal 5, @variant.reload.stock_quantity
    patch bo_product_variant_path(org_slug: @org.slug, product_id: @product.id, id: @variant.id), params: {
      product_variant: { stock_source: "erp", stock_quantity: "99" }
    }
    assert_response :redirect
    assert_equal "erp", @variant.reload.stock_source
    assert_equal 5, @variant.stock_quantity
  end
  test "BO creates and edits an order with local stock" do
    customer = @org.customers.create!(company_name: "Buyer", contact_name: "Ana", active: true)
    user = customer.customer_users.create!(organisation: @org, email: "buyer-stock@example.test",
      password: "password123", password_confirmation: "password123", contact_name: "Ana", active: true)
    @variant.update!(stock_source: "nodal", stock_policy: "show_badge")
    post bo_orders_path(org_slug: @org.slug), params: {
      order: { customer_id: customer.id, order_items_attributes: [{ product_variant_id: @variant.id, quantity: 3 }] }
    }
    assert_response :redirect
    order = @org.orders.placed.last
    assert_equal user, order.customer_user
    assert_equal @admin, order.placed_by
    assert_equal 7, @variant.reload.stock_quantity

    patch bo_order_path(org_slug: @org.slug, id: order.id), params: {
      order: { order_items_attributes: [{ id: order.order_items.first.id, quantity: 11 }] }
    }
    assert_response :unprocessable_entity
    assert_equal 7, @variant.reload.stock_quantity
    assert_equal 3, order.order_items.first.reload.quantity

    patch bo_order_path(org_slug: @org.slug, id: order.id), params: {
      order: { order_items_attributes: [{ id: order.order_items.first.id, _destroy: "1" }] }
    }
    assert_response :redirect
    assert_equal 10, @variant.reload.stock_quantity
  end

end
