module DiscountScopeHelper
  def order_line_pricing(order)
    @order_line_pricing ||= {}
    @order_line_pricing[order.object_id] ||= OrderLinePricing.new(order)
  end

  def automatic_campaign_description(order)
    snapshot = order.auto_discount_scope_snapshot
    if snapshot
      scope = snapshot["discount"]
      names = Array(scope["categories"]).map { |category| category["name"] }.join(', ')
      description = case scope["mode"]
      when "include" then "Apenas: #{names}"
      when "exclude" then "Todos exceto: #{names}"
      else "Todos os artigos"
      end
      "#{snapshot['campaign_name']} · #{description}"
    elsif !order.placed? && (campaign = order.best_order_discount&.order_discount_campaign)
      "#{campaign.name} · #{campaign.discount_scope.description}"
    end
  end
end
