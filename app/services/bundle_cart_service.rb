class BundleCartService
  def initialize(order)
    @order = order
  end

  def add!(product, quantity)
    quantity = Integer(quantity.to_s, 10)
    raise ArgumentError, I18n.t("bundles.errors.quantity") unless quantity.positive?
    @order.with_lock do
      raise ArgumentError, I18n.t("bundles.errors.unavailable") unless @order.draft? &&
        product.organisation_id == @order.organisation_id && product.bundle_purchasable?
      components = product.bundle_components.includes(product_variant: :product).order(:id).to_a
      group = @order.order_bundles.create!(product: product, name: product.name, quantity: quantity,
        unit_price_cents: product.unit_price, composition: components.map { |c|
          { variant_id: c.product_variant_id, name: c.product_variant.product.name,
            variant: c.product_variant.option_values_string, sku: c.product_variant.sku, quantity: c.quantity }
        })
      allocations = allocate(components, product.unit_price)
      components.each do |component|
        variant = component.product_variant
        line = @order.order_items.build(product: variant.product, product_variant: variant, order_bundle: group,
          quantity: component.quantity * quantity, bundle_component_quantity: component.quantity,
          unit_price: allocations.fetch(component.id).fdiv(component.quantity).round,
          bundle_amount_cents: allocations.fetch(component.id), discount_percentage: 0)
        line.preserve_calculated_discount = true
        line.save!
      end
      @order.order_items.reset
      raise ArgumentError, I18n.t("bundles.errors.insufficient_stock") if group.capacity_in_cart < quantity
      group
    end
  end

  def update!(group, quantity)
    quantity = Integer(quantity.to_s, 10)
    raise ArgumentError, I18n.t("bundles.errors.quantity") unless quantity.positive?
    @order.with_lock do
      raise ArgumentError, I18n.t("bundles.errors.unavailable") unless @order.draft? && group.order_id == @order.id
      group.update!(quantity: quantity)
      group.order_items.each { |item| item.update!(quantity: item.bundle_component_quantity * quantity) }
      @order.order_items.reset
      raise ArgumentError, I18n.t("bundles.errors.insufficient_stock") if group.capacity_in_cart < quantity
    end
  end

  def refresh_price!(group)
    return false if @order.placed? || group.unit_price_cents == group.product.unit_price || !group.current_composition?
    @order.with_lock do
      components = group.product.bundle_components.includes(:product_variant).order(:id).to_a
      allocations = allocate(components, group.product.unit_price)
      group.update!(unit_price_cents: group.product.unit_price)
      group.order_items.each do |item|
        component = components.find { |part| part.product_variant_id == item.product_variant_id }
        cents = allocations.fetch(component.id)
        item.update!(bundle_amount_cents: cents, unit_price: cents.fdiv(component.quantity).round)
      end
      @order.order_items.reset
    end
    true
  end

  private

  def allocate(components, total)
    BundlePriceAllocation.call(components, total)
  end
end
