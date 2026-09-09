module StockDisplayHelper
  # How much stock to admit to, for whoever is looking. Nil means say nothing,
  # which is the answer for anyone without permission, for an organisation that
  # shows no quantities, and for a variant that does not track stock at all.
  #
  # The band is computed here rather than in the browser on purpose: when the
  # organisation chose bands, the exact figure must not reach the page at all.
  # Sending the number and rendering a word would publish the number.
  # `beside_availability` is for the places that already say "In stock" in
  # words. There, a band reading "Available" says the same thing twice — only
  # the warning adds anything, so the comfortable band stays quiet. Standing on
  # its own, as in the grid's column, a band has to say something either way.
  def stock_display_label(variant, beside_availability: false)
    return nil unless may_see_stock_quantities?
    return nil unless variant&.track_stock?

    quantity = variant.stock_quantity.to_i

    return t("storefront.products.show.stock_units", count: quantity) if current_organisation.shows_exact_stock?

    return nil if quantity <= 0 # already said by the out-of-stock line
    return t("storefront.products.show.stock_low") if quantity <= current_organisation.low_stock_threshold.to_i

    beside_availability ? nil : t("storefront.products.show.stock_available")
  end
end
