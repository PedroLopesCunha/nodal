class VariantAttributeValue < ApplicationRecord
  belongs_to :product_variant
  belongs_to :product_attribute_value

  validates :product_attribute_value_id, uniqueness: { scope: :product_variant_id }

  delegate :value, :slug, :color_hex, :product_attribute, to: :product_attribute_value
end
