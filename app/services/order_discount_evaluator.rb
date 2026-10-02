class OrderDiscountEvaluator
  Result = Struct.new(:discount, :campaign, :qualification_cents, :discount_base_cents,
    :discount_amount, :allocations, keyword_init: true)

  def initialize(order)
    @order = order
    @currency = order.organisation.currency
    @context = CartDiscountContext.new(order.order_items.includes(:product_variant, product: :categories).to_a)
  end

  def evaluate(discount)
    campaign = discount.order_discount_campaign
    qualification = @context.amount_cents_for(scope: campaign&.qualification_scope, basis: :after_line_discounts)
    items = @context.items_for(scope: campaign&.discount_scope)
    base = items.sum { |item| item.total_price.cents }
    amount = if qualification < discount.min_order_amount_cents || base <= 0
      Money.new(0, @currency)
    elsif discount.percentage?
      Money.new(base, @currency) * discount.discount_value
    else
      Money.new([(discount.discount_value * 100).to_i, base].min, @currency)
    end
    Result.new(discount: discount, campaign: campaign, qualification_cents: qualification,
      discount_base_cents: base, discount_amount: amount, allocations: allocate(items, base, amount.cents))
  end

  def selected
    candidates = @order.organisation.order_discounts.active
      .includes(order_discount_campaign: { category_scopes: :categories }).map { |discount| evaluate(discount) }
      .select { |result| result.qualification_cents >= result.discount.min_order_amount_cents && result.discount_base_cents > 0 }
    winners = candidates.group_by { |result| result.campaign&.id }.values.map do |tiers|
      tiers.min_by { |result| [-result.discount.min_order_amount_cents, result.discount.id] }
    end
    winners.min_by { |result| [result.campaign&.priority || 1, result.campaign&.id || 0] }
  end

  private

  # Largest-remainder allocation: deterministic, exact in cents and bounded
  # by each eligible line. These amounts are before the existing global cap.
  def allocate(items, base, cents)
    return {} if base <= 0 || cents <= 0
    shares = items.map do |item|
      numerator = item.total_price.cents * cents
      [item.id, numerator / base, numerator % base]
    end
    remaining = cents - shares.sum { |_, amount, _| amount }
    shares.sort_by { |id, _, remainder| [-remainder, id] }.first(remaining).each { |share| share[1] += 1 }
    shares.to_h { |id, amount, _| [id, amount] }
  end
end
