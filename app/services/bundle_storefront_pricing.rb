class BundleStorefrontPricing
  def initialize(product:, customer: nil, base_prices: false)
    @product = product
    @base_prices = base_prices
    @customer = base_prices ? nil : customer
    @currency = product.organisation.currency
  end

  def call
    components = @product.bundle_components.includes(product_variant: :product).order(:id).to_a
    allocations = BundlePriceAllocation.call(components, @product.unit_price)
    lines = components.map do |component|
      variant = component.product_variant
      separate = variant.price * component.quantity
      unless @base_prices
        discount = DiscountCalculator.new(product: variant.product, variant: variant, customer: @customer,
          quantity: component.quantity, include_erp_discount: false).effective_discount[:percentage] || 0
        separate -= separate * discount
      end
      separate = apply_erp(separate)
      included = apply_erp(Money.new(allocations.fetch(component.id), @currency))
      { component: component, separate_total: separate, bundle_total: included,
        separate_unit: BigDecimal(separate.cents.to_s) / 100 / component.quantity,
        bundle_unit: BigDecimal(included.cents.to_s) / 100 / component.quantity }
    end
    separate = lines.sum(Money.new(0, @currency)) { |line| line[:separate_total] }
    price = lines.sum(Money.new(0, @currency)) { |line| line[:bundle_total] }
    { separate: separate, price: price, savings: [separate - price, Money.new(0, @currency)].max, lines: lines }
  end

  private

  def apply_erp(amount)
    rate = @customer&.erp_discount_percentage.to_d / 100
    amount - amount * rate
  end
end
