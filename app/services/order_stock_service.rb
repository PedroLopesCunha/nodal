# Only Nodal-managed quantities are changed here. The per-line counter is a
# receipt of consumption, not a movement history: legacy orders start at zero.
class OrderStockService
  def initialize(order)
    @order = order
  end

  def synchronize
    Order.transaction do
      persisted = Order.lock.find(@order.id) if @order.persisted?
      previous = persisted ? persisted.order_items.to_a : []
      ids = (previous.map(&:product_variant_id) + @order.order_items.map(&:product_variant_id)).compact.uniq
      # Products are locked first because availability is shared by siblings.
      Product.where(id: ProductVariant.where(id: ids).select(:product_id)).order(:id).lock.load
      variants = ProductVariant.where(id: ids).order(:id).lock.index_by(&:id)
      yield persisted, previous, variants
    end
  end

  def save
    synchronize do |persisted, previous, variants|
      result = yield
      next if result == false
      next unless @order.placed?

      current = OrderItem.where(order_id: @order.id).to_a
      movements = Hash.new(0)
      previous_by_id = previous.index_by(&:id)
      receipts = {}

      previous.each do |item|
        movements[item.product_variant_id] -= item.local_stock_consumed if variants[item.product_variant_id]&.nodal_stock?
      end

      current.each do |item|
        variant = variants[item.product_variant_id]
        old = previous_by_id[item.id]
        consumed = 0
        if variant&.nodal_stock?
          consumed = if !persisted&.placed? || old.nil? || old.product_variant_id != item.product_variant_id
            item.quantity
          else
            # Do not retroactively consume legacy orders, or quantities sold
            # while the variant was ERP-managed. Only subsequent increases.
            [old.local_stock_consumed + item.quantity - old.quantity, 0].max
          end
          movements[variant.id] += consumed
        end
        receipts[item.id] = consumed
      end

      movements.each do |id, quantity|
        next if quantity.zero?
        variant = variants.fetch(id)
        enforce_stock!(variant, quantity) if quantity.positive?
        variant.update!(stock_quantity: variant.stock_quantity.to_i - quantity)
        StockRulesService.new(@order.organisation).apply_to_variant(variant)
      end
      current_by_id = current.index_by(&:id)
      loaded_by_id = @order.order_items.target.index_by(&:id)
      receipts.each do |id, quantity|
        item = loaded_by_id[id] || current_by_id.fetch(id)
        if current_by_id.fetch(id).local_stock_consumed != quantity || item.local_stock_consumed != quantity
          item.update_columns(local_stock_consumed: quantity)
        end
      end
    end
  end

  def destroy
    synchronize do |persisted, previous, variants|
      result = yield
      next if result == false
      next unless persisted&.placed? && persisted.status == "in_process"

      previous.group_by(&:product_variant_id).each do |id, items|
        variant = variants[id]
        quantity = items.sum(&:local_stock_consumed)
        next unless variant&.nodal_stock? && quantity.positive?

        variant.update!(stock_quantity: variant.stock_quantity.to_i + quantity)
        StockRulesService.new(@order.organisation).apply_to_variant(variant)
      end
    end
  end

  private

  def enforce_stock!(variant, quantity)
    return if variant.sells_without_stock? || quantity <= variant.stock_quantity.to_i
    if @order.stock_checkout_context
      policy = @order.organisation.checkout_stock_policy
      return if policy == "allow"
      return if policy == "warn" && ActiveModel::Type::Boolean.new.cast(@order.confirmed_stock_warnings)
    end

    @order.errors.add(:base, I18n.t("stock_management.insufficient", name: variant.name))
    raise ActiveRecord::RecordInvalid, @order
  end
end
