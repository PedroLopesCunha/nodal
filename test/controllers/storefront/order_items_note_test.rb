require "test_helper"

# Covers per-line cart notes: a customer can attach an observation to a cart
# line via #update, it persists, and it renders on the cart and checkout pages.
class Storefront::OrderItemsNoteTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @org = Organisation.create!(name: "Note Org", currency: "EUR")
    @customer = @org.customers.create!(company_name: "Cliente Lda", contact_name: "João",
                                       email: "cli@example.com", active: true)
    @customer_user = CustomerUser.create!(
      email: "buyer@example.com", password: "password123",
      organisation: @org, customer: @customer, active: true
    )
    @product = Product.create!(organisation: @org, name: "Camisa", sku: "CAM-001",
                               unit_price: 1999, published: true, available: true)
    sign_in @customer_user
  end

  def cart
    @customer_user.orders.draft.find_by(organisation: @org)
  end

  def add_item
    post order_items_path(org_slug: @org.slug),
         params: { product_id: @product.id, order_item: { quantity: 1 } }
    cart.order_items.find_by(product: @product)
  end

  test "updating a line saves its note" do
    item = add_item
    patch order_item_path(org_slug: @org.slug, id: item),
          params: { order_item: { note: "Entregar sem embalagem" } }
    assert_redirected_to cart_path(org_slug: @org.slug)
    assert_equal "Entregar sem embalagem", item.reload.note
  end

  test "the note renders on the cart and checkout pages" do
    item = add_item
    item.update!(note: "Cor à escolha do cliente")

    get cart_path(org_slug: @org.slug)
    assert_response :success
    assert_includes @response.body, "Cor à escolha do cliente"

    get checkout_path(org_slug: @org.slug)
    assert_response :success
    assert_includes @response.body, "Cor à escolha do cliente"
  end

  test "a note over 500 chars is rejected with an alert" do
    item = add_item
    patch order_item_path(org_slug: @org.slug, id: item),
          params: { order_item: { note: "a" * 501 } }
    assert_redirected_to cart_path(org_slug: @org.slug)
    assert_nil item.reload.note
  end
end
