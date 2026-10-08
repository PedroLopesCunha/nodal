require "test_helper"

class Bo::ProductsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @organisation = Organisation.create!(name: "Products Catalog Org", currency: "EUR")
    @admin = Member.create!(email: "products-admin@example.com", password: "password123",
                            first_name: "Ana", last_name: "Admin")
    @organisation.org_members.create!(member: @admin, role: "owner", active: true)
    sign_in @admin
  end

  # Regression guard: the catalog modals/partials were parameterized so the
  # sales-rep page can reuse them. The admin flow must keep working with the
  # default (products-scoped) URLs when no locals are passed.
  test "admin products index renders the catalog modals" do
    get bo_products_path(org_slug: @organisation.slug)
    assert_response :success
  end

  test "admin catalog selection partial renders" do
    get catalog_selection_bo_products_path(org_slug: @organisation.slug)
    assert_response :success
  end
  test "product search matches attributes of simple and unpublished variable products" do
    attribute = @organisation.product_attributes.create!(name: "Cor", display_type: "dropdown", card_display_mode: "values")
    value = attribute.product_attribute_values.create!(value: "Encarnádo exclusivo")
    simple = @organisation.products.create!(name: "Produto Simples", unit_price: 1000)
    simple.default_variant.attribute_values << value
    variable = @organisation.products.create!(name: "Produto Variavel", has_variants: true, published: false)
    variant = variable.product_variants.create!(organisation: @organisation, name: "Opcao", is_default: false, published: false)
    variant.attribute_values << value
    other = @organisation.products.create!(name: "Outro Produto", unit_price: 1000)

    get bo_products_path(org_slug: @organisation.slug, query: "encarnado exclusivo")
    assert_response :success
    assert_select ".product-row", count: 2
    assert_select ".product-row", text: /Produto Simples/, count: 1
    assert_select ".product-row", text: /Produto Variavel/, count: 1
    assert_select ".product-row", text: /Outro Produto/, count: 0
  end

  test "product search still matches description" do
    @organisation.products.create!(name: "Produto", unit_price: 1000, description: "acabamento singularissimo")
    get bo_products_path(org_slug: @organisation.slug, query: "singularissimo")
    assert_response :success
    assert_select ".product-row", count: 1
  end

end
