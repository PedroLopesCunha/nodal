module CartHelper
  # Returns a stock badge for a cart line, or nil when the item is fine to buy.
  def cart_stock_badge(item)
    case item.stock_status
    when :out_of_stock, :variant_unpublished
      content_tag(:span, t("storefront.carts.show.stock.out_of_stock"),
                  class: "badge bg-danger-subtle text-danger")
    when :qty_overflow
      available = item.product_variant.stock_quantity.to_i
      content_tag(:span, t("storefront.carts.show.stock.only_n_left", count: available),
                  class: "badge bg-warning-subtle text-warning")
    end
  end
end
