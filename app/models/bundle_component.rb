class BundleComponent < ApplicationRecord
  belongs_to :product, inverse_of: :bundle_components
  belongs_to :product_variant
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :product_variant_id, uniqueness: { scope: :product_id }
  after_save :refresh_bundle
  after_destroy :refresh_bundle
  validate :valid_component

  private

  def refresh_bundle
    Product.find_by(id: product_id)&.refresh_bundle_inventory! unless product.destroyed?
  end

  def valid_component
    return unless product_variant && product
    unless product_variant.organisation_id == product.organisation_id
      errors.add(:product_variant, :invalid)
    end
    if product_variant.product.bundle? || (product_variant.product.has_variants? && product_variant.is_default?)
      errors.add(:product_variant, I18n.t("bundles.errors.invalid_component"))
    end
    errors.add(:product_variant, :invalid) if product_variant.unit_price_cents.nil?
  end
end
