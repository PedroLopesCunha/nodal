class OrderLinePricing
  Line = Struct.new(:original_total, :total, :unit_price, :campaign_savings, :campaign_percentage, keyword_init: true)

  def initialize(order)
    @order = order
    @evaluation = order.automatic_discount_evaluation unless order.placed?
  end

  # Presentation only: OrderItem#total_price remains the base used by the engine.
  # Allocations are before coupons, shipping, tax and the organisation discount cap.
  def line(item)
    cents = if @order.placed?
      item.auto_order_discount_amount_cents.to_i
    else
      @evaluation&.allocations&.fetch(item.id, 0) || 0
    end
    savings = Money.new(cents, item.price.currency)
    total = item.total_price - savings
    type = @order.placed? ? @order.auto_discount_type : @evaluation&.discount&.discount_type
    value = @order.placed? ? @order.auto_discount_value : @evaluation&.discount&.discount_value
    Line.new(original_total: item.price * item.quantity, total: total,
      unit_price: total / item.quantity, campaign_savings: savings,
      campaign_percentage: type == 'percentage' ? value : nil)
  end
end
