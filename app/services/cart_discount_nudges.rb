# Finds "you're almost there" discount opportunities for a cart: conditional
# discounts (quantity or €) the customer is close to unlocking but hasn't yet.
# Used to nudge the customer to add a little more. Only surfaces opportunities
# at >= THRESHOLD_RATIO of the goal, to stay relevant (less is more).
#
# A per-line discount is evaluated on each cart line (variant) independently —
# so on a variable product one variant can be unlocked while another still
# needs a nudge, exactly like separate simple products. A summed
# discount is evaluated on the aggregate, one entry for the whole product/category.
class CartDiscountNudges
  THRESHOLD_RATIO = 0.65

  # One unlock opportunity, ready to render. `remaining` is a Money (amount
  # condition) or an Integer of units (quantity condition); `condition_type`
  # says which, so the view formats it.
  Opportunity = Struct.new(
    :label, :discount_label, :progress, :remaining, :condition_type, :reward,
    :units_to_add, :add_product_id, :add_variant_id, :sku,
    keyword_init: true
  )

  # A conditional discount the customer has now reached (to celebrate).
  Unlocked = Struct.new(:label, :discount_label, :reward, keyword_init: true)

  def initialize(order)
    @order = order
    @org = order.organisation
    @currency = @org.currency
    @context = CartDiscountContext.new(order.order_items.includes(:product_variant, product: :categories).to_a)
  end

  def opportunities
    candidate_discounts.flat_map { |d| build_opportunities(d) }.compact
                       .sort_by { |o| -o.progress }
  end

  # Conditional discounts whose threshold is now met — to celebrate.
  def unlocked
    candidate_discounts.flat_map { |d| build_unlockeds(d) }.compact
  end

  private

  # Per-line conditions are evaluated independently even for category rules.
  def per_line?(discount)
    !discount.summed_condition?
  end

  def lines_for_discount(discount)
    @context.items_for(scope: discount.discount_scope, product_id: discount.product_id, exclude_variants: true)
  end

  def build_opportunities(discount)
    if per_line?(discount)
      lines_for_discount(discount).filter_map { |item| build_opportunity_line(discount, item) }
    else
      # NB: [x].compact, not Array(x) — Array() would decompose the Struct into
      # its field values.
      [build_opportunity_aggregate(discount)].compact
    end
  end

  def build_unlockeds(discount)
    if per_line?(discount)
      lines_for_discount(discount).filter_map { |item| build_unlocked_line(discount, item) }
    else
      [build_unlocked_aggregate(discount)].compact
    end
  end

  # --- per-line: a single cart variant line -----------------------------
  # Base line value (before discount) and the threshold, in the condition's unit.
  def line_inputs(discount, item)
    if discount.amount_condition?
      [(item.price * item.quantity).cents, discount.min_amount_cents.to_i]
    else
      [item.quantity, discount.min_quantity.to_i]
    end
  end

  def build_opportunity_line(discount, item)
    current, threshold = line_inputs(discount, item)
    return if threshold <= 0

    progress = current.to_f / threshold
    return if progress < THRESHOLD_RATIO || progress >= 1.0

    qty = item.quantity
    amount = (item.price * item.quantity).cents
    add = units_to_add(discount, threshold, qty, amount)

    Opportunity.new(
      label: item.product.name,
      discount_label: discount_value_label(discount),
      progress: progress,
      remaining: remaining_for(discount, threshold, current),
      condition_type: discount.condition_type.to_sym,
      reward: projected_reward(discount, qty, amount, add),
      units_to_add: add,
      add_product_id: item.product_id,
      add_variant_id: item.product_variant_id,
      sku: variant_sku(item)
    )
  end

  def build_unlocked_line(discount, item)
    current, threshold = line_inputs(discount, item)
    return if threshold <= 0 || current < threshold

    return unless applied_to_line?(discount, item)
    saved = (item.price * item.quantity - item.total_price).cents
    return if saved <= 0

    Unlocked.new(label: item.product.name, discount_label: discount_value_label(discount), reward: Money.new(saved, @currency))
  end

  # --- aggregate: product or category total -----------------------------
  def build_opportunity_aggregate(discount)
    current, threshold, remaining = progress_for(discount)
    return if threshold <= 0
    progress = current.to_f / threshold
    return if progress < THRESHOLD_RATIO || progress >= 1.0

    selection = qualification_selection(discount)
    qty = @context.quantity_for(**selection)
    amount = @context.amount_cents_for(**selection)
    add = units_to_add(discount, threshold, qty, amount)
    Opportunity.new(label: discount.display_name, discount_label: discount_value_label(discount),
      progress: progress, remaining: remaining, condition_type: discount.condition_type.to_sym,
      reward: projected_reward(discount, qty, amount, add), units_to_add: add,
      add_product_id: discount.product_id, add_variant_id: nil, sku: discount.product&.sku)
  end

  def build_unlocked_aggregate(discount)
    current, threshold, = progress_for(discount)
    return if threshold <= 0 || current < threshold
    cents = lines_for_discount(discount).sum do |item|
      applied_to_line?(discount, item) ? (item.price * item.quantity - item.total_price).cents : 0
    end
    return if cents <= 0
    Unlocked.new(label: discount.display_name, discount_label: discount_value_label(discount), reward: Money.new(cents, @currency))
  end

  def applied_to_line?(discount, item)
    DiscountCalculator.new(product: item.product, customer: @order.customer, quantity: item.quantity,
      variant: item.product_variant, cart_context: @context).applied_discounts.any? { |applied| applied[:source] == discount }
  end

  def candidate_discounts
    @order.order_items.filter_map do |item|
      next unless item.product
      DiscountCalculator.new(product: item.product, customer: @order.customer, quantity: item.quantity,
        variant: item.product_variant, cart_context: @context, for_display: true).all_discounts
        .select { |discount| discount[:condition] }.map { |discount| discount[:source] }
    end.flatten.uniq
  end

  def qualification_selection(discount)
    { scope: discount.qualification_scope, product_id: discount.product_id, exclude_variants: true }
  end

  def progress_for(discount)
    selection = qualification_selection(discount)
    current = discount.amount_condition? ? @context.amount_cents_for(**selection) : @context.quantity_for(**selection)
    threshold = discount.amount_condition? ? discount.min_amount_cents.to_i : discount.min_quantity.to_i
    [current, threshold, remaining_for(discount, threshold, current)]
  end

  def remaining_for(discount, threshold, current)
    if discount.amount_condition?
      Money.new([threshold - current, 0].max, @currency)
    else
      [threshold - current, 0].max
    end
  end

  # Units of the target the customer must add to cross the threshold. For a €
  # condition we divide the shortfall by the cart's average unit price; for a
  # quantity condition it's simply the remaining count.
  def units_to_add(discount, threshold, qty, amount)
    if discount.amount_condition?
      avg = qty.positive? ? amount.to_f / qty : 0
      avg.positive? ? ((threshold - amount) / avg).ceil : 0
    else
      [threshold - qty, 0].max
    end
  end

  # € saved once the threshold is reached by adding `add` units. Uses the same
  # rounded per-unit discount the cart applies (round(price * rate)), so it
  # agrees with the "Desconto -€X" the summary will show after the add.
  def projected_reward(discount, qty, amount, add)
    projected_qty = qty + add
    avg = qty.positive? ? amount.to_f / qty : 0
    per_unit = discount.percentage? ? (avg * discount.discount_value).round : (discount.discount_value * 100).to_i
    Money.new([per_unit * projected_qty, 0].max, @currency)
  end

  def discount_value_label(discount)
    if discount.percentage?
      "-#{(discount.discount_value * 100).round}%"
    else
      "-#{Money.new((discount.discount_value * 100).to_i, @currency).format}"
    end
  end

  def discount_target_label(discount, by_category)
    by_category ? discount.category&.name : discount.product&.name
  end

  def variant_sku(item)
    (item.product_variant&.sku.presence if item.product&.variable?) || item.product&.sku
  end
end
