module BundleProduct
  extend ActiveSupport::Concern

  included do
    has_many :bundle_components, inverse_of: :product, dependent: :destroy
    has_many :order_bundles, dependent: :restrict_with_error
    accepts_nested_attributes_for :bundle_components, allow_destroy: true, reject_if: ->(a) { a["product_variant_id"].blank? }
    validate :validate_bundle
    after_save :refresh_bundle_inventory!
    after_save :refresh_containing_bundles!
    scope :bundles, -> { where(bundle: true) }
  end

  def bundle_capacity
    parts = bundle_components.reject(&:marked_for_destruction?)
    return 0 if parts.size < 2
    parts.map do |part|
      variant = part.product_variant
      next 0 unless variant&.published? && variant.product.published? && variant.purchasable?
      variant.sells_without_stock? ? Float::INFINITY : [variant.stock_quantity.to_i / part.quantity, 0].max
    end.min
  end

  def bundle_purchasable?
    bundle? && published? && bundle_capacity.positive?
  end

  def refresh_bundle_inventory!
    return unless bundle?
    capacity = bundle_capacity
    update_columns(available: capacity.positive?) if available? != capacity.positive?
    default_variant&.update_columns(stock_quantity: capacity.finite? ? capacity : 0,
      track_stock: capacity.finite?, stock_source: "nodal", exclude_from_discounts: true)
  end

  def refresh_containing_bundles!
    Product.where(id: BundleComponent.where(product_variant_id: product_variants.select(:id)).select(:product_id))
      .find_each(&:refresh_bundle_inventory!)
  end

  def containing_bundles
    organisation.products.bundles.where(published: true,
      id: BundleComponent.where(product_variant_id: product_variants.select(:id)).select(:product_id))
  end

  private

  def validate_bundle
    return unless bundle?
    errors.add(:base, I18n.t("bundles.errors.simple_only")) if has_variants? || price_on_request?
    errors.add(:price, :invalid) if unit_price.nil? || unit_price.negative?
    parts = bundle_components.reject(&:marked_for_destruction?)
    errors.add(:base, I18n.t("bundles.errors.minimum_components")) if parts.size < 2
    ids = parts.map(&:product_variant_id)
    errors.add(:base, I18n.t("bundles.errors.duplicate_components")) if ids.uniq.size != ids.size
    errors.add(:sku, I18n.t("bundles.errors.no_erp_reference")) if sku.present?
    if persisted? && will_save_change_to_bundle? && order_items.exists?
      errors.add(:base, I18n.t("bundles.errors.cannot_convert"))
    end
  end
end
