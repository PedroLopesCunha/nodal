module StockDisplayHelper
  # How much stock to admit to, for whoever is looking. Nil means say nothing,
  # which is the answer for anyone without permission, for an organisation that
  # shows no quantities, and for a variant that does not track stock at all.
  #
  # The band is computed here rather than in the browser on purpose: when the
  # organisation chose bands, the exact figure must not reach the page at all.
  # Sending the number and rendering a word would publish the number.
  def stock_display_label(variant)
    return nil unless may_see_stock_quantities?
    return nil unless variant&.track_stock?

    quantity = variant.stock_quantity.to_i

    if current_organisation.shows_exact_stock?
      t("storefront.products.show.stock_units", count: quantity)
    elsif quantity <= 0
      nil # already said by the out-of-stock line above it
    elsif quantity <= current_organisation.low_stock_threshold.to_i
      t("storefront.products.show.stock_low")
    else
      t("storefront.products.show.stock_available")
    end
  end
end
