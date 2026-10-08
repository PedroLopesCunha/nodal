require "test_helper"

class VariantGeneratorServiceTest < ActiveSupport::TestCase
  setup do
    @org = Organisation.create!(name: "Variant Generation Org", currency: "EUR")
    @product = @org.products.create!(name: "Camisa", unit_price: 1000)
    @base = @product.default_variant
    attribute = @org.product_attributes.create!(name: "Cor", display_type: "dropdown", card_display_mode: "values")
    @blue = attribute.product_attribute_values.create!(value: "Azul")
    @red = attribute.product_attribute_values.create!(value: "Vermelho")
    @product.product_attributes << attribute
    @product.available_attribute_values << [@blue, @red]
    @base.attribute_values << @blue
  end

  test "conversion clears base attributes while preserving its identity and configured values" do
    base_id = @base.id
    @product.update!(has_variants: true)

    assert @base.reload.is_default?
    assert_equal base_id, @product.reload.default_variant.id
    assert_empty @base.attribute_values.reload
    assert_equal [@blue.id, @red.id].sort, @product.available_attribute_values.ids.sort

    result = VariantGeneratorService.new(@product).call
    assert result[:success]
    assert_equal 2, result[:variants_created]
    assert_equal 0, result[:variants_skipped]
    assert_equal [[@blue.id], [@red.id]].sort,
      @product.product_variants.where(is_default: false).map { |variant| variant.attribute_values.ids }.sort

    repeated = VariantGeneratorService.new(@product.reload).call
    assert_equal 0, repeated[:variants_created]
    assert_equal 2, repeated[:variants_skipped]
    assert_equal 3, @product.product_variants.count
  end

  test "legacy base attributes do not block generation and remain untouched" do
    @product.update_column(:has_variants, true)
    result = VariantGeneratorService.new(@product.reload).call

    assert result[:success]
    assert_equal 2, result[:variants_created]
    assert_equal 0, result[:variants_skipped]
    assert @base.reload.is_default?
    assert_equal [@blue.id], @base.attribute_values.ids
  end
end
