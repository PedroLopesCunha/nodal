class OrderLinePricing
  Line = Struct.new(:original_total, :total, :unit_price, :campaign_savings, :campaign_percentage,
    :line_discount_percentage, keyword_init: true)

  def initialize(order, include_erp_discount: true)
    @order = order
    @include_erp_discount = include_erp_discount
    @evaluation = order.automatic_discount_evaluation unless order.placed?
  end

  def replaced_line_savings
    @replaced_line_savings ||= if @order.placed?
      (@order.auto_discount_scope_snapshot || {}).fetch('replaced_line_savings', {}).transform_keys(&:to_i)
    else
      @evaluation&.replaced_line_savings || {}
    end
  end

  def line_discount_amount
    @order.gross_subtotal - @order.total_amount - Money.new(replaced_line_savings.values.sum, @order.organisation.currency)
  end

  def campaign_discount_amount
    amount = @order.placed? ? @order.auto_order_discount_amount : (@evaluation&.discount_amount || Money.new(0, @order.organisation.currency))
    amount + Money.new(replaced_line_savings.values.sum, @order.organisation.currency)
  end

  def subtotal_before_campaign
    @order.gross_subtotal - line_discount_amount
  end

  # Allocate order-wide Nodal adjustments (coupons, manual discount and cap)
  # to lines before exporting. Largest remainders preserve the exact subtotal.
  # This calculation never includes the ERP-owned discount.
  def export_totals
    @export_totals ||= begin
      internal = self.class.new(@order, include_erp_discount: false)
      items = @order.order_items.to_a
      # Unsaved nested lines also participate when BO updates trigger tax pricing.
      bases = items.to_h { |item| [item.id || -item.object_id, internal.line(item).total.cents] }
      target = @order.nodal_subtotal_after_discount.cents
      base = bases.values.sum
      if target > base
        # A cap restores savings. Allocate only against the amounts actually
        # discounted, so no line can be exported above its original price.
        savings = items.to_h do |item|
          key = item.id || -item.object_id
          [key, (item.price * item.quantity).cents - bases.fetch(key)]
        end
        restored = allocate_cents(savings, target - base)
        bases.to_h { |key, cents| [key, cents + restored.fetch(key, 0)] }
      else
        allocate_cents(bases, target)
      end
    end
  end

  # Presentation only: OrderItem#total_price remains the base used by the engine.
  # Allocations are before coupons, shipping, tax and the organisation discount cap.
  def line(item)
    cents = if @order.placed?
      item.auto_order_discount_amount_cents.to_i
    else
      @evaluation&.allocations&.fetch(item.id, 0) || 0
    end
    additional_savings = Money.new(cents, item.price.currency)
    savings = additional_savings + Money.new(replaced_line_savings.fetch(item.id, 0), item.price.currency)
    total = item.total_price - additional_savings
    total -= total * @order.erp_discount_rate if @include_erp_discount
    type = @order.placed? ? @order.auto_discount_type : @evaluation&.discount&.discount_type
    value = @order.placed? ? @order.auto_discount_value : @evaluation&.discount&.discount_value
    Line.new(original_total: item.price * item.quantity, total: total,
      unit_price: total / item.quantity, campaign_savings: savings,
      campaign_percentage: type == 'percentage' ? value : nil,
      line_discount_percentage: replaced_line_savings.key?(item.id) ? 0 : item.discount_percentage)
  end

  private

  def allocate_cents(weights, target)
    base = weights.values.sum
    return weights.transform_values { 0 } if base.zero?

    shares = weights.map { |id, amount| [id, amount * target / base, amount * target % base] }
    remaining = target - shares.sum { |_, cents, _| cents }
    shares.sort_by { |id, _, remainder| [-remainder, id] }.first(remaining).each { |share| share[1] += 1 }
    shares.to_h { |id, cents, _| [id, cents] }
  end

end
