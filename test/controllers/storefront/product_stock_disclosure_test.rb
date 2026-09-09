require "test_helper"

# The product page serialises every variant into a data attribute for the
# variant selector. It used to include the real stock quantity, which no script
# ever read — so the exact figure for every variant sat in the page source of
# every product, readable by anyone, while the page itself only ever said "in
# stock" or "out of stock".
#
# Whether a customer may see quantities is a decision for the organisation to
# make. Until it does, the number does not leave the server.
class Storefront::ProductStockDisclosureTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @org = Organisation.create!(name: "Stock Disclosure Org", currency: "EUR")
    @customer = @org.customers.create!(company_name: "Cliente Lda", contact_name: "João",
                                       email: "cli-stock@example.com", active: true)
    @customer_user = CustomerUser.create!(
      email: "buyer-stock@example.com", password: "password123",
      organisation: @org, customer: @customer, active: true
    )

    @attribute = @org.product_attributes.create!(name: "Cor", display_type: "dropdown", card_display_mode: "values")
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

    sign_in @customer_user
  end

  def variant_payload
    get product_path(org_slug: @org.slug, id: @product.id)
    assert_response :success

    node = css_select("[data-variant-selector-variants-value]").first
    assert_not_nil node, "the product page should carry the variant payload"
    JSON.parse(node["data-variant-selector-variants-value"])
  end

  test "the page does not publish how many units are in stock" do
    payload = variant_payload

    assert_equal 1, payload.size
    assert_not payload.first.key?("stock_quantity"),
      "the exact quantity must not be sent to the browser"
  end

  # Deliberately an absurd quantity: a short number turns up inside asset
  # digests and record ids, so the test would fail for reasons that have
  # nothing to do with stock. Seven specific digits in a row will not.
  test "the quantity appears nowhere in the page" do
    get product_path(org_slug: @org.slug, id: @product.id)

    assert_response :success
    assert_no_match(/8675309/, response.body)
  end

  # What the page is supposed to say about stock, it still says.
  test "the page still knows whether a variant can be bought" do
    variant = variant_payload.first

    assert_equal true, variant["in_stock"]
    assert_equal true, variant["track_stock"]
    assert_equal true, variant["purchasable"]
  end

  test "an out of stock variant is still reported as such" do
    @variant.update!(stock_quantity: 0)

    variant = variant_payload.first

    assert_equal false, variant["in_stock"]
  end
end
