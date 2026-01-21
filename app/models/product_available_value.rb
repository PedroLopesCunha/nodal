class ProductAvailableValue < ApplicationRecord
  belongs_to :product
  belongs_to :product_attribute_value

  validates :product_attribute_value_id, uniqueness: { scope: :product_id }
  validate :attribute_assigned_to_product

  delegate :value, :slug, :color_hex, to: :product_attribute_value
  delegate :product_attribute, to: :product_attribute_value

  private

  def attribute_assigned_to_product
    return if product.nil? || product_attribute_value.nil?

    attribute = product_attribute_value.product_attribute
    unless product.product_attributes.include?(attribute)
      errors.add(:product_attribute_value, "belongs to an attribute not assigned to this product")
    end
  end
end
