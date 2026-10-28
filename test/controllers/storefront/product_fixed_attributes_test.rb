require "test_helper"

class Storefront::ProductFixedAttributesTest < ActionDispatch::IntegrationTest
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

  setup do
    @size = @org.product_attributes.create!(name: "Tamanho", display_type: "dropdown", card_display_mode: "values")
    @medium = @size.product_attribute_values.create!(value: "M")
    @product.product_attributes << @size
    @product.available_attribute_values << @medium
    @variant.attribute_values << @medium
    @red = @attribute.product_attribute_values.create!(value: "Vermelho")
    @product.available_attribute_values << @red
    @red_variant = @product.product_variants.create!(organisation: @org, name: "Vermelho / M", sku: "RED-M",
      unit_price_cents: 1999, unit_price_currency: "EUR", published: true, available: true, is_default: false)
    @red_variant.attribute_values << [@red, @medium]
  end

  test "grid quick add shows bulk quantities and returns saved rows on partial failure" do
    @org.update!(quick_add_enabled: true)
    @product.update!(add_to_cart_mode: "grid")
    get quick_add_product_path(org_slug: @org.slug, id: @product)
    assert_response :success
    assert_select '.quick-add-rows', count: 1
    assert_select '.quantity-stepper input[value="0"]', count: 2
    assert_select '.quick-add-bulk-footer button[disabled]', count: 1
    assert_select 'input[name="quick_add"][value="1"]', count: 1
    assert_select 'input[name=?]', "bulk_items[#{@variant.id}]", count: 1
    assert_select 'textarea[name="order_item[note]"]', count: 1

    post bulk_add_order_items_path(org_slug: @org.slug), params: {
      product_id: @product.id, quick_add: "1", bulk_items: { @variant.id.to_s => "2", "0" => "1" },
      order_item: { note: "Separar por tamanho" }
    }, as: :json
    assert_response :unprocessable_entity
    assert_equal [@variant.id], response.parsed_body["added_variant_ids"]
    assert_equal 1, response.parsed_body["cart_count"]
    item = @customer_user.current_cart(@org).order_items.find_by!(product_variant: @variant)
    assert_equal 2, item.quantity
    assert_equal "Separar por tamanho", item.note

    post bulk_add_order_items_path(org_slug: @org.slug), params: {
      product_id: @product.id, quick_add: "1", bulk_items: { @red_variant.id.to_s => "3" }
    }, as: :json
    assert_response :success
    assert_equal [@red_variant.id], response.parsed_body["added_variant_ids"]
    assert_equal 2, response.parsed_body["cart_count"]
  end

  test "quick add reuses variant choices and fixed attributes" do
    @org.update!(quick_add_enabled: true)
    get quick_add_product_path(org_slug: @org.slug, id: @product)
    assert_response :success
    assert_select 'input[data-single-attribute-value=?]', @medium.id.to_s, count: 1
    assert_select 'select[data-variant-selector-target=select]', count: 1
    assert_select 'textarea[name="order_item[note]"]', count: 1
    assert_select '[data-controller~=variant-selector]', count: 1
  end

  test "default mode shows shared size outside the selector and preserves automatic value" do
    get product_path(org_slug: @org.slug, id: @product.id)
    assert_response :success
    assert_select "input[data-single-attribute-value='#{@medium.id}']", count: 1
    assert_select "input[data-single-attribute-value='#{@medium.id}']" do |inputs|
      assert_includes inputs.first.parent.text, "Tamanho:"
      assert_includes inputs.first.parent.text, "M"
    end
    assert_select "select[data-variant-selector-target=select]", count: 1
    assert_select "select[data-variant-selector-target=select] option[value='#{@red.id}']", count: 1
  end

  test "grid displays common size once and only colors in row labels" do
    @product.update!(add_to_cart_mode: "grid")
    get product_path(org_slug: @org.slug, id: @product.id)
    assert_response :success
    assert_select ".fw-semibold", text: "Tamanho:", count: 1
    assert_select "table thead", text: /Cor/
    assert_select "table thead", text: /Tamanho/, count: 0
    assert_select "table tbody .fw-medium", text: "Azul", count: 1
    assert_select "table tbody .fw-medium", text: "Vermelho", count: 1
    assert_select "input[name='bulk_items[#{@variant.id}]']", count: 1
    assert_select "input[name='bulk_items[#{@red_variant.id}]']", count: 1
  end

  test "grid ignores unpriced variants when deriving fixed attributes" do
    @product.update!(add_to_cart_mode: "grid")
    @red_variant.update!(unit_price_cents: 0)
    get product_path(org_slug: @org.slug, id: @product.id)
    assert_response :success
    assert_select ".fw-semibold", text: "Cor:", count: 1
    assert_select "input[name='bulk_items[#{@red_variant.id}]']", count: 0
  end

  test "all fixed attributes retain hidden values without selection heading" do
    @red_variant.update!(published: false)
    get product_path(org_slug: @org.slug, id: @product.id)
    assert_response :success
    assert_select "input[data-single-attribute-value]", count: 2
    assert_select "select[data-variant-selector-target=select]", count: 0
    assert_select "h6", text: I18n.t("storefront.products.show.select_options"), count: 0
  end
  test "existing variants remain selectable when generation configuration is narrower" do
    @product.product_available_values.where(product_attribute_value_id: @red.id).destroy_all
    get product_path(org_slug: @org.slug, id: @product.id)
    assert_response :success
    assert_select "select[data-variant-selector-target=select] option[value='#{@red.id}']", count: 1
    assert_select "select[data-variant-selector-target=select] option[value='#{@blue.id}']", count: 1

    @product.update!(add_to_cart_mode: "grid")
    get product_path(org_slug: @org.slug, id: @product.id)
    assert_response :success
    assert_select "table tbody .fw-medium", text: "Azul", count: 1
    assert_select "table tbody .fw-medium", text: "Vermelho", count: 1
  end

end
