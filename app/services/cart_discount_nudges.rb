# Finds "you're almost there" discount opportunities for a cart: conditional
# discounts (quantity or €) the customer is close to unlocking but hasn't yet.
# Used to nudge the customer to add a little more. Only surfaces opportunities
# at >= THRESHOLD_RATIO of the goal, to stay relevant (less is more).
class CartDiscountNudges
  THRESHOLD_RATIO = 0.65

  # One unlock opportunity, ready to render. `remaining` is a Money (amount
  # condition) or an Integer of units (quantity condition); `condition_type`
  # says which, so the view formats it.
  Opportunity = Struct.new(
    :label, :discount_label, :progress, :remaining, :condition_type, :reward,
    :units_to_add, :add_product_id, :sku,
    keyword_init: true
  )

  # A conditional discount the customer has now reached (to celebrate).
  Unlocked = Struct.new(:label, :discount_label, :reward, keyword_init: true)

  def initialize(order)
    @order = order
    @org = order.organisation
    @currency = @org.currency
    @context = CartDiscountContext.new(order.order_items.includes(product: :categories).to_a)
  end

  def opportunities
    candidate_discounts.filter_map { |discount| build_opportunity(discount) }
                       .sort_by { |o| -o.progress }
  end

  # Conditional discounts whose threshold is now met — to celebrate.
  def unlocked
    candidate_discounts.filter_map { |discount| build_unlocked(discount) }
  end

  private

  def build_unlocked(discount)
    by_category = discount.category_id.present?
    target_id = by_category ? discount.category_id : discount.product_id

    current, threshold, = progress_for(discount, by_category, target_id)
    return if threshold.to_i <= 0 || current < threshold

    Unlocked.new(
      label: discount_target_label(discount, by_category),
      discount_label: discount_value_label(discount),
      reward: current_reward(discount, by_category, target_id)
    )
  end

  # € saved right now on the current cart contents — the effective saving on
  # the target's line items (gross - discounted total), so the celebration
  # badge matches the "Desconto -€X" line in the order summary to the cent
  # (both derive from the same rounded per-unit prices).
  def current_reward(discount, by_category, target_id)
    cents = items_for_target(by_category, target_id).sum do |item|
      (item.price * item.quantity - item.total_price).cents
    end
    Money.new([cents, 0].max, @currency)
  end

  def items_for_target(by_category, target_id)
    @order.order_items.select do |item|
      next false unless item.product
      if by_category
        item.product.categories.flat_map(&:path_ids).include?(target_id)
      else
        item.product_id == target_id
      end
    end
  end

  def candidate_discounts
    product_ids = @order.order_items.map(&:product_id).uniq.compact
    return [] if product_ids.empty?

    category_ids = Product.where(id: product_ids).includes(:categories)
                          .flat_map { |p| p.categories.flat_map(&:path_ids) }.uniq

    discounts = ProductDiscount.active.where(organisation: @org)
                               .where("condition_type IN (?)", %w[quantity amount])
                               .where("product_id IN (?) OR category_id IN (?)", product_ids, category_ids)
                               .to_a

    if (customer = @order.customer)
      cpd = CustomerProductDiscount.active.where(organisation: @org)
                                   .where("condition_type IN (?)", %w[quantity amount])
                                   .where("product_id IN (?) OR category_id IN (?)", product_ids, category_ids)
      discounts += cpd.where(customer_id: customer.id).to_a
      discounts += cpd.where(customer_category_id: customer.customer_category_id).to_a if customer.customer_category_id
    end

    discounts.uniq
  end

  def build_opportunity(discount)
    by_category = discount.category_id.present?
    target_id = by_category ? discount.category_id : discount.product_id

    current, threshold, remaining = progress_for(discount, by_category, target_id)
    return if threshold.to_i <= 0

    progress = current.to_f / threshold
    return if progress < THRESHOLD_RATIO || progress >= 1.0

    qty = by_category ? @context.category_quantity(target_id) : @context.product_quantity(target_id)
    amount = by_category ? @context.category_amount_cents(target_id) : @context.product_amount_cents(target_id)
    add = units_to_add(discount, threshold, qty, amount)

    Opportunity.new(
      label: discount_target_label(discount, by_category),
      discount_label: discount_value_label(discount),
      progress: progress,
      remaining: remaining,
      condition_type: discount.condition_type.to_sym,
      reward: projected_reward(discount, qty, amount, add),
      units_to_add: add,
      # The "add N units" button only makes sense for a single product, not a
      # whole category (which product would we add?).
      add_product_id: by_category ? nil : discount.product_id,
      sku: by_category ? nil : discount.product&.sku
    )
  end

  def progress_for(discount, by_category, target_id)
    if discount.amount_condition?
      current = by_category ? @context.category_amount_cents(target_id) : @context.product_amount_cents(target_id)
      threshold = discount.min_amount_cents.to_i
      remaining = Money.new([threshold - current, 0].max, @currency)
    else
      current = by_category ? @context.category_quantity(target_id) : @context.product_quantity(target_id)
      threshold = discount.min_quantity.to_i
      remaining = [threshold - current, 0].max
    end
    [current, threshold, remaining]
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
end
