module PriceDisplayHelper
  def format_discount_percentage(decimal_percentage)
    "#{(decimal_percentage * 100).round(0)}%"
  end

  def show_prices?
    !current_customer_user&.hide_prices?
  end
end
