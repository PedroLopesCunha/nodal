class OrderDiscountEvaluator
  Result = Struct.new(:discount, :campaign, :qualification_cents, :discount_base_cents,
    :discount_amount, :allocations, :replaced_line_savings, keyword_init: true)

  def initialize(order)
    @order = order
    @currency = order.organisation.currency
    @context = CartDiscountContext.new(order.order_items.includes(:product_variant, product: :categories).to_a)
    @line_stackable = {}
  end

  def evaluate(discount)
    campaign = discount.order_discount_campaign
    qualification = @context.amount_cents_for(scope: campaign&.qualification_scope, basis: :after_line_discounts)
    items = @context.items_for(scope: campaign&.discount_scope)
    bases = items.to_h do |item|
      [item.id, stacks_with_line?(discount, item) ? item.total_price.cents : (item.price * item.quantity).cents]
    end
    base = bases.values.sum
    amount = if qualification < discount.min_order_amount_cents || base <= 0
      Money.new(0, @currency)
    elsif discount.percentage?
      Money.new(base, @currency) * discount.discount_value
    else
      Money.new([(discount.discount_value * 100).to_i, base].min, @currency)
    end
    candidates = allocate(bases, base, amount.cents)
    allocations = {}
    replaced = {}
    items.each do |item|
      candidate = candidates.fetch(item.id, 0)
      old_saving = (item.price * item.quantity - item.total_price).cents
      if stacks_with_line?(discount, item)
        allocations[item.id] = candidate if candidate.positive?
      elsif candidate > old_saving
        # The engine retains the qualification price. Only the additional saving
        # is deducted from that price; the full campaign saving is old + additional.
        allocations[item.id] = candidate - old_saving
        replaced[item.id] = old_saving if old_saving.positive?
      end
    end
    Result.new(discount: discount, campaign: campaign, qualification_cents: qualification,
      discount_base_cents: base, discount_amount: Money.new(allocations.values.sum, @currency),
      allocations: allocations, replaced_line_savings: replaced)
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

  def stacks_with_line?(discount, item)
    return false unless discount.stackable?
    return true if (item.price * item.quantity - item.total_price).zero?
    unless @line_stackable.key?(item.id)
      applied = DiscountCalculator.new(product: item.product, customer: @order.customer,
        quantity: item.quantity, variant: item.product_variant, cart_context: @context).applied_discounts
      # Compare against the complete existing line price. A bundle can accumulate
      # only when every contributing rule consents; unattributed prices are exclusive.
      @line_stackable[item.id] = applied.any? && applied.all? { |rule| rule[:stackable] }
    end
    @line_stackable[item.id]
  end

  # Largest-remainder allocation: deterministic, exact in cents and bounded
  # by each eligible line. These amounts are before the existing global cap.
  def allocate(bases, base, cents)
    return {} if base <= 0 || cents <= 0
    shares = bases.map do |id, line_base|
      numerator = line_base * cents
      [id, numerator / base, numerator % base]
    end
    remaining = cents - shares.sum { |_, amount, _| amount }
    shares.sort_by { |id, _, remainder| [-remainder, id] }.first(remaining).each { |share| share[1] += 1 }
    shares.to_h { |id, amount, _| [id, amount] }
  end
end
