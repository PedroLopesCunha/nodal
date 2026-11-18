module BundlesHelper
  def bundle_opportunity?(product)
    @bundle_component_product_ids ||= BundleComponent.joins(:product, :product_variant)
      .where(products: { organisation_id: current_organisation.id, bundle: true, published: true, available: true })
      .distinct.pluck("product_variants.product_id").to_set
    !product.bundle? && @bundle_component_product_ids.include?(product.id)
  end

  def bundle_comparison(product)
    @bundle_comparisons ||= {}
    @bundle_comparisons[product.id] ||= BundleStorefrontPricing.new(product: product,
      customer: current_customer, base_prices: browsing_as_member?).call
  end

  # Round only the displayed unit price; cart allocations retain exact cents.
  def bundle_unit_price(amount)
    money_amount(Money.new((amount * 100).round.to_i, current_organisation.currency))
  end
end
