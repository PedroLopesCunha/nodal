class StockRulesService
  def initialize(organisation)
    @organisation = organisation
  end

  def apply_to_variant(variant)
    return unless variant.track_stock?

    policy = variant.effective_stock_policy
    # track_only: stock doesn't affect availability
    if policy == 'track_only'
      variant.update_column(:available, true) unless variant.available
    else
      # show_badge or hide: available reflects actual stock
      new_available = variant.stock_quantity.to_i > 0
      variant.update_column(:available, new_available) if variant.available != new_available
    end

    recalculate_product_availability(variant.product)
  end

  def recalculate_product_availability(product)
    variants = product.product_variants
    # For variable products, exclude the base/default variant (not sold separately)
    variants = variants.where(is_default: false) if product.has_variants? && variants.where(is_default: false).exists?
    # A product is available if at least one variant is published AND has stock
    any_available = variants.where(published: true, available: true).exists?
    product.update_column(:available, any_available) if product.available != any_available
  end
end
