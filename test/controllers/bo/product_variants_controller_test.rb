require "test_helper"
require Rails.root.join("db/migrate/20261008120000_clear_default_flag_from_real_variable_variants")

class Bo::ProductVariantsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @org = Organisation.create!(name: "Internal Base Org", currency: "EUR")
    member = Member.create!(email: "internal-base@example.com", password: "password123", first_name: "Ana", last_name: "Admin")
    @org.org_members.create!(member: member, role: "owner", active: true)
    sign_in member
    @product = @org.products.create!(name: "Camisa", has_variants: true)
    @base = @product.default_variant
    attribute = @org.product_attributes.create!(name: "Cor", display_type: "dropdown", card_display_mode: "values")
    @blue = attribute.product_attribute_values.create!(value: "Azul")
    @product.product_attributes << attribute
    @product.available_attribute_values << @blue
    @variant = @product.product_variants.create!(name: "Azul", unit_price_cents: 1000, is_default: false)
    @variant.attribute_values << @blue
  end

  test "edit does not offer the internal default flag" do
    [@variant, @base].each do |variant|
      get edit_bo_product_variant_path(org_slug: @org.slug, product_id: @product.id, id: variant.id)
      assert_response :success
      assert_select "input[name='product_variant[is_default]']", count: 0
    end
  end

  test "update cannot change the internal default flag" do
    [[@variant, "1", false], [@base, "0", true]].each do |variant, flag, expected|
      patch bo_product_variant_path(org_slug: @org.slug, product_id: @product.id, id: variant.id),
        params: { product_variant: { name: variant.name, is_default: flag, attribute_value_ids: variant.attribute_values.ids } }
      assert_response :redirect
      assert_equal expected, variant.reload.is_default?
    end
  end

  test "repair clears real variable flags and preserves internal and simple defaults" do
    @variant.update_column(:is_default, true)
    simple = @org.products.create!(name: "Simples", unit_price: 1000)
    simple.default_variant.attribute_values << @blue
    ActiveRecord::Migration.suppress_messages { ClearDefaultFlagFromRealVariableVariants.new.up }
    assert_not @variant.reload.is_default?
    assert @base.reload.is_default?
    assert simple.default_variant.reload.is_default?
  end

  test "repair preserves a legacy base with attributes without recreating variants" do
    @base.attribute_values << @blue
    @base.update_column(:unit_price_cents, nil)
    original_ids = @product.product_variants.ids.sort

    ActiveRecord::Migration.suppress_messages { ClearDefaultFlagFromRealVariableVariants.new.up }

    assert @base.reload.is_default?
    assert_nil @base.unit_price_cents
    assert_not @variant.reload.is_default?
    assert_equal original_ids, @product.product_variants.ids.sort
  end

  test "repair preserves multiple attribute-bearing defaults without a separate base" do
    @base.attribute_values << @blue
    @variant.update_column(:is_default, true)

    ActiveRecord::Migration.suppress_messages { ClearDefaultFlagFromRealVariableVariants.new.up }

    assert @base.reload.is_default?
    assert @variant.reload.is_default?
  end
  test "configuration converts using the chosen real variant and keeps its data" do
    @variant.update!(sku: "BLUE-UNIT", stock_source: "nodal", track_stock: true, stock_quantity: 12)
    @variant.photo.attach(io: StringIO.new("image"), filename: "blue.png", content_type: "image/png")
    other = @product.product_variants.create!(name: "Other", unit_price_cents: 2000, is_default: false)
    ids = @product.product_variants.ids.sort
    patch update_variant_configuration_bo_product_path(org_slug: @org.slug, id: @product.id),
      params: { has_variants: "0", simple_variant_id: @variant.id }
    assert_response :redirect
    assert_not @product.reload.has_variants?
    assert_equal @variant.id, @product.default_variant.id
    assert_equal 1000, @product.unit_price
    assert_equal "BLUE-UNIT", @product.sku
    assert_equal 12, @variant.reload.stock_quantity
    assert_equal "nodal", @variant.stock_source
    assert @variant.track_stock?
    assert_equal [@blue.id], @variant.attribute_values.ids
    assert_equal [@blue.id], @product.available_attribute_values.ids
    assert_equal @variant.photo.blob_id, @product.cover_photo_blob_id
    assert_equal ids, @product.product_variants.ids.sort
    assert_not @base.reload.is_default?
    assert_not other.reload.is_default?
  end

  test "configuration automatically chooses the only real variant" do
    patch update_variant_configuration_bo_product_path(org_slug: @org.slug, id: @product.id),
      params: { has_variants: "0" }
    assert_response :redirect
    assert_equal @variant.id, @product.reload.default_variant.id
    assert_not @product.has_variants?
  end

  test "conversion rejects missing or foreign selection without modifying product" do
    other = @product.product_variants.create!(name: "Other", unit_price_cents: 2000, is_default: false)
    foreign = @org.products.create!(name: "Foreign", unit_price: 2000).default_variant
    [nil, foreign.id, @base.id].each do |id|
      patch update_variant_configuration_bo_product_path(org_slug: @org.slug, id: @product.id),
        params: { has_variants: "0", simple_variant_id: id }
      assert_response :unprocessable_entity
      assert @product.reload.has_variants?
      assert @base.reload.is_default?
      assert_not @variant.reload.is_default?
      assert_not other.reload.is_default?
    end
  end

  test "variable simple variable round trip restores base without clearing the real variant" do
    @variant.update!(sku: "BLUE-ROUND", stock_source: "nodal", stock_quantity: 12, track_stock: true)
    @variant.photo.attach(io: StringIO.new("image"), filename: "round.png", content_type: "image/png")
    original_ids = @product.product_variants.ids.sort
    original_data = @variant.reload.attributes.slice("sku", "unit_price_cents", "stock_quantity", "track_stock", "stock_source")

    2.times do
      patch update_variant_configuration_bo_product_path(org_slug: @org.slug, id: @product.id),
        params: { has_variants: "0", simple_variant_id: @variant.id }
      assert_response :redirect
      assert_equal @base.id, @product.reload.variable_base_variant_id
      assert_equal @variant.id, @product.default_variant.id

      patch update_variant_configuration_bo_product_path(org_slug: @org.slug, id: @product.id),
        params: { has_variants: "1", product: { product_attribute_ids: [@blue.product_attribute_id], available_attribute_value_ids: [@blue.id] } }
      assert_response :redirect
      assert @product.reload.has_variants?
      assert_equal @base.id, @product.default_variant.id
      assert_nil @product.variable_base_variant_id
      assert @base.reload.is_default?
      assert_not @variant.reload.is_default?
      assert_equal original_data, @variant.attributes.slice(*original_data.keys)
      assert_equal [@blue.id], @variant.attribute_values.ids
      assert @variant.photo.attached?
      assert_equal original_ids, @product.product_variants.ids.sort
      assert_equal [@base.id], @product.product_variants.where(is_default: true).ids
    end
  end

end
