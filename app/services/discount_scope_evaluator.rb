# Category selection is independent of monetary basis and variant policies.
class DiscountScopeEvaluator
  def initialize(items)
    @items = items
  end

  def items_for(scope:, product_id: nil, exclude_variants: false)
    @items.select do |item|
      item.product && (!product_id || item.product_id == product_id) &&
        (!scope || scope.matches_product?(item.product)) &&
        (!exclude_variants || !item.product_variant&.exclude_from_discounts?)
    end
  end

  def quantity_for(**selection)
    items_for(**selection).sum { |item| item.quantity.to_i }
  end

  def amount_cents_for(basis: :base, **selection)
    raise ArgumentError, "Unknown monetary basis" unless basis.in?(%i[base after_line_discounts])
    items_for(**selection).sum do |item|
      amount = basis == :base ? item.price * item.quantity : item.total_price
      amount.cents
    end
  end
end
