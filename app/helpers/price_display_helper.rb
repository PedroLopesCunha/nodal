module PriceDisplayHelper
  # Canonical price formatting for the storefront. Unlike
  # humanized_money_with_symbol, this always shows two decimals (€85,00 not
  # €85), matching the live JS pricing (toFixed(2)) so amounts never read
  # inconsistently side by side.
  def money_amount(value)
    return value unless value.respond_to?(:format)
    value.format
  end

  def format_discount_percentage(decimal_percentage)
    "#{(decimal_percentage * 100).round(0)}%"
  end

  def show_prices?
    !current_customer_user&.hide_prices?
  end
end
