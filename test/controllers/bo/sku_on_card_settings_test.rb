require "test_helper"

# Guards the two new fields are permitted and persist: the org-level toggle on
# the storefront settings form, and the per-product suppression on the product
# form.
class Bo::SkuOnCardSettingsTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @organisation = Organisation.create!(name: "SKU Card Org", currency: "EUR")
    @member = Member.create!(
      email: "sku-admin@example.com",
      password: "password123",
      first_name: "Sku",
      last_name: "Admin"
    )
    @organisation.org_members.create!(member: @member, role: "owner", active: true)
    sign_in @member
  end

  test "quick add settings persist independently" do
    assert_not @organisation.quick_add_enabled?
    patch bo_settings_path(org_slug: @organisation.slug), params: { organisation: { quick_add_enabled: "1" } }
    assert @organisation.reload.quick_add_enabled?
    product = Product.create!(organisation: @organisation, name: "Quick Product", sku: "QP1")
    assert product.quick_add_enabled?
    patch bo_product_path(org_slug: @organisation.slug, id: product.id), params: { product: { quick_add_enabled: "0" } }
    assert_not product.reload.quick_add_enabled?
  end

  test "settings form persists the org-level show_product_sku_on_card toggle" do
    assert_not @organisation.show_product_sku_on_card, "should default off"

    patch bo_settings_path(org_slug: @organisation.slug), params: {
      organisation: { show_product_sku_on_card: "1" }
    }
    assert @organisation.reload.show_product_sku_on_card
  end

  test "product form persists the per-product hide_sku_on_card flag" do
    product = Product.create!(organisation: @organisation, name: "Widget", sku: "W1")

    patch bo_product_path(org_slug: @organisation.slug, id: product.id), params: {
      product: { hide_sku_on_card: "1" }
    }
    assert product.reload.hide_sku_on_card
  end
end
