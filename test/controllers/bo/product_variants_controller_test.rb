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
end
