require "test_helper"

class Storefront::QuickAddTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @org = Organisation.create!(name: "Quick Add Shop", currency: "EUR", quick_add_enabled: true)
    customer = @org.customers.create!(company_name: "Buyer", contact_name: "Buyer", email: "quick-buyer@example.com", active: true)
    @user = CustomerUser.create!(email: "quick-user@example.com", password: "password123", organisation: @org, customer: customer, active: true)
    @product = @org.products.create!(name: "Quick Widget", sku: "QUICK-1", published: true, available: true)
    @variant = @product.default_variant
    @variant.update!(unit_price_cents: 1250, published: true, available: true)
    sign_in @user
  end

  test "organisation and product independently gate quick add" do
    get products_path(org_slug: @org.slug)
    assert_select '[data-controller="quick-add"]', count: 1
    @product.update!(quick_add_enabled: false)
    get products_path(org_slug: @org.slug)
    assert_select '[data-controller="quick-add"]', count: 0
    get quick_add_product_path(org_slug: @org.slug, id: @product)
    assert_response :not_found
    @product.update!(quick_add_enabled: true)
    @org.update!(quick_add_enabled: false)
    get quick_add_product_path(org_slug: @org.slug, id: @product)
    assert_response :not_found
  end

  test "panel contains quantity notes and details without the layout" do
    get quick_add_product_path(org_slug: @org.slug, id: @product)
    assert_response :success
    assert_select 'input[name="order_item[quantity]"]', count: 1
    assert_select 'textarea[name="order_item[note]"]', count: 1
    assert_select 'a[href=?]', product_path(org_slug: @org.slug, id: @product)
    assert_select 'nav', count: 0
  end

  test "quick add confirms without redirect and preserves distinct notes" do
    add = ->(note) {
      post order_items_path(org_slug: @org.slug), params: {
        product_id: @product.id, variant_id: @variant.id, quick_add: "1",
        order_item: { quantity: 1, note: note }
      }, as: :json
      assert_response :success
    }
    add.call("First")
    add.call("Second")
    add.call("First")
    items = @user.current_cart(@org).order_items
    assert_equal 2, items.count
    assert_equal 2, items.find_by!(note: "First").quantity
    assert_equal 1, items.find_by!(note: "Second").quantity
    assert_equal 2, response.parsed_body["cart_count"]
  end

  test "validation errors are returned without adding a line" do
    post order_items_path(org_slug: @org.slug), params: {
      product_id: @product.id, variant_id: @variant.id, quick_add: "1", order_item: { quantity: 0 }
    }, as: :json
    assert_response :unprocessable_entity
    assert_equal 0, @user.current_cart(@org).order_items.count
  end
end
