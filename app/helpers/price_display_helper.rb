module PriceDisplayHelper
  def format_discount_percentage(decimal_percentage)
    "#{(decimal_percentage * 100).round(0)}%"
  end

  def show_prices?
    !current_customer&.hide_prices?
  end
end
