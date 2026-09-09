require "test_helper"

# Who may see how much stock there is. The rule lives in one place
# (Storefront::BaseController#may_see_stock_quantities?) and is enforced on the
# server: a quantity that reaches the browser is disclosed whatever the page
# renders, which is how the figure ended up in every product's page source
# before.
class Storefront::StockVisibilityTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @org = Organisation.create!(name: "Stock Visibility Org", currency: "EUR",
                                storefront_stock_display: "exact")
    @customer = @org.customers.create!(company_name: "Cliente Lda", contact_name: "João",
                                       email: "cli-vis@example.com", active: true)
    @customer_user = CustomerUser.create!(
      email: "buyer-vis@example.com", password: "password123",
      organisation: @org, customer: @customer, active: true
    )

    @attribute = @org.product_attributes.create!(name: "Cor", display_type: "dropdown",
                                                 card_display_mode: "values")
    @blue = @attribute.product_attribute_values.create!(value: "Azul")

    @product = Product.create!(organisation: @org, name: "Camisa", sku: "CAM-001",
                               published: true, available: true, has_variants: true)
    @product.product_attributes << @attribute
    @product.available_attribute_values << @blue

    @variant = @product.product_variants.create!(
      organisation: @org, name: "Azul", sku: "CAM-001-AZ",
      unit_price_cents: 1999, unit_price_currency: "EUR",
      published: true, available: true, is_default: false,
      track_stock: true, stock_quantity: 8_675_309
    )
    @variant.attribute_values << @blue
  end

  def variant_payload
    get product_path(org_slug: @org.slug, id: @product.id)
    assert_response :success

    node = css_select("[data-variant-selector-variants-value]").first
    assert_not_nil node
    JSON.parse(node["data-variant-selector-variants-value"]).first
  end

  def assert_quantity_hidden
    assert_not variant_payload.key?("stock_quantity"),
      "the quantity must not be sent to someone who may not see it"
    assert_no_match(/8675309/, response.body)
  end

  def assert_quantity_shown
    assert_equal 8_675_309, variant_payload["stock_quantity"]
  end

  test "a customer without permission is told nothing about quantities" do
    sign_in @customer_user

    assert_quantity_hidden
  end

  test "a customer whose company was granted it sees the quantity" do
    @customer.update!(sees_stock_quantities: true)
    sign_in @customer_user

    assert_quantity_shown
  end

  # The permission belongs to the company, so every login of that company has
  # it — the trust was extended to the account, not to one person.
  test "every login of a permitted company sees it" do
    @customer.update!(sees_stock_quantities: true)
    colleague = CustomerUser.create!(email: "colleague-vis@example.com", password: "password123",
                                     organisation: @org, customer: @customer, active: true)
    sign_in colleague

    assert_quantity_shown
  end

  # The organisation's setting comes first: with it off, nobody sees a quantity,
  # however many companies have been granted permission.
  test "nobody sees quantities while the organisation shows none" do
    @org.update!(storefront_stock_display: "none")
    @customer.update!(sees_stock_quantities: true)
    sign_in @customer_user

    assert_quantity_hidden
  end

  test "granting permission to one company says nothing about another" do
    @customer.update!(sees_stock_quantities: true)
    other = @org.customers.create!(company_name: "Outra Lda", contact_name: "Ana",
                                   email: "outra-vis@example.com", active: true)
    other_login = CustomerUser.create!(email: "outra-buyer@example.com", password: "password123",
                                       organisation: @org, customer: other, active: true)
    sign_in other_login

    assert_quantity_hidden
  end

  # Our own people. A back office member browsing the shop, and a rep working
  # through a company that has no permission of its own, both see quantities:
  # they are working, and the shop is where they work.
  def member(role: "owner", sales_rep: false)
    m = Member.create!(email: "member-vis-#{SecureRandom.hex(3)}@example.com", password: "password123",
                       first_name: "Ana", last_name: "Admin")
    @org.org_members.create!(member: m, role: role, active: true, is_sales_rep: sales_rep)
    m
  end

  test "a member browsing the shop sees quantities" do
    sign_in member

    assert_quantity_shown
  end

  test "a rep impersonating a company without permission still sees quantities" do
    rep = member(sales_rep: true)
    sign_in rep

    post bo_impersonation_path(org_slug: @org.slug), params: { customer_id: @customer.id }

    assert_not @customer.reload.sees_stock_quantities?, "the company itself must not have permission"
    assert_quantity_shown
  end

  # The organisation's setting still comes first, even for our own people.
  test "a member sees no quantities while the organisation shows none" do
    @org.update!(storefront_stock_display: "none")
    sign_in member

    assert_quantity_hidden
  end
end
