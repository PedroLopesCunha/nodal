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

  # Live-pricing payload for the bulk grid (grid add-to-cart mode). Returns nil
  # when there's no conditional discount to track. Per-variant locked/unlocked
  # prices + the product's conditional discount, so the grid-pricing JS can flip
  # row prices (per_line) or run a single summed tracker.
  def grid_live_pricing(product, variants)
    return nil unless show_prices?

    cart = current_cart && CartDiscountContext.new(current_cart.order_items.includes(product: :categories).to_a)
    conditional = DiscountCalculator.new(product: product, customer: current_customer, for_display: true, variant: nil)
                                    .all_discounts.find { |d| d[:condition] }
    return nil unless conditional

    cond = conditional[:condition]
    summed = cond[:scope] == :summed
    min_qty = product.quantity_input_min

    pricing = variants.each_with_object({}) do |v, hash|
      next unless v.unit_price_cents.to_i.positive?

      locked = DiscountCalculator.new(product: product, customer: current_customer, quantity: min_qty, for_display: false, variant: v, cart_context: cart).final_price
      unlocked = DiscountCalculator.new(product: product, customer: current_customer, quantity: min_qty, for_display: true, variant: v, cart_context: cart).final_price
      hash[v.id] = {
        locked: locked.cents, unlocked: unlocked.cents, base: v.unit_price_cents,
        cart: variant_cart_toward(cart, product, v, cond, summed)
      }
    end

    {
      pricing: pricing,
      condition_type: cond[:type].to_s,
      threshold: cond[:type] == :amount ? cond[:amount].cents : cond[:quantity],
      scope: cond[:scope].to_s,
      cart_summed: summed ? variant_cart_toward(cart, product, nil, cond, true) : 0,
      discount_label: conditional[:discount_type] == "percentage" ? "-#{(conditional[:value] * 100).round}%" : "-#{Money.new((conditional[:value] * 100).to_i, current_organisation.currency).format}"
    }
  end

  def variant_cart_toward(cart, product, variant, cond, summed)
    return 0 unless cart

    if summed
      cond[:type] == :amount ? cart.product_amount_cents(product.id) : cart.product_quantity(product.id)
    else
      cond[:type] == :amount ? cart.variant_amount_cents(variant.id) : cart.variant_quantity(variant.id)
    end
  end

  def show_prices?
    !current_customer_user&.hide_prices?
  end
end
