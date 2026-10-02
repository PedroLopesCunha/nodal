class OrderLinePricing
  Line = Struct.new(:original_total, :total, :unit_price, :campaign_savings, :campaign_percentage,
    :line_discount_percentage, keyword_init: true)

  def initialize(order)
    @order = order
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
    type = @order.placed? ? @order.auto_discount_type : @evaluation&.discount&.discount_type
    value = @order.placed? ? @order.auto_discount_value : @evaluation&.discount&.discount_value
    Line.new(original_total: item.price * item.quantity, total: total,
      unit_price: total / item.quantity, campaign_savings: savings,
      campaign_percentage: type == 'percentage' ? value : nil,
      line_discount_percentage: replaced_line_savings.key?(item.id) ? 0 : item.discount_percentage)
  end
end
