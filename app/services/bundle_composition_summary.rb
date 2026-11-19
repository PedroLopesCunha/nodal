# Back-office composition uses base prices and physical tracked stock, even
# when a component's sale policy permits backorders. No stock is reserved.
class BundleCompositionSummary
  class InvalidComposition < StandardError; end

  def initialize(organisation:, components:, price_cents: nil)
    @organisation = organisation
    @components = components
    @price_cents = price_cents
  end

  def call
    parts = @components.filter_map do |part|
      part = part.to_h.symbolize_keys
      next if part[:product_variant_id].blank?
      id = Integer(part[:product_variant_id].to_s, exception: false)
      quantity = Integer(part[:quantity].to_s, exception: false)
      fail_with("quantity") unless id && quantity&.positive?
      { id: id, quantity: quantity }
    end
    ids = parts.map { |part| part[:id] }
    fail_with("duplicate_components") unless ids.uniq.size == ids.size
    variants = @organisation.product_variants.real_units.where(id: ids).includes(:product).index_by(&:id)
    fail_with("invalid_component") unless variants.size == ids.size
    lines = parts.map do |part|
      variant = variants.fetch(part[:id])
      price = variant.unit_price_cents
      stock = variant.track_stock? ? variant.stock_quantity.to_i : nil
      capacity = stock.nil? ? nil : [stock / part[:quantity], 0].max
      {
        variant_id: variant.id, label: variant.picker_label, product_id: variant.product_id,
        quantity: part[:quantity], unit_price_cents: variant.unit_price_cents,
        subtotal_cents: price && price * part[:quantity], stock_quantity: stock, capacity: capacity,
        unit_price: money(price), subtotal: money(price && price * part[:quantity]),
        stock: stock.nil? ? I18n.t("bundles.stock_untracked") : stock.to_s
      }
    end
    total = lines.any? { |line| line[:subtotal_cents].nil? } ? nil : lines.sum { |line| line[:subtotal_cents] }
    capacity = lines.filter_map { |line| line[:capacity] }.min
    difference = @price_cents.nil? || total.nil? || lines.empty? ? nil : total - @price_cents
    percentage = difference && total&.positive? ? (BigDecimal(difference.to_s) * 100 / total).round(2).to_f : nil
    {
      lines: lines, total_cents: total, total: money(total), capacity: capacity,
      stock: lines.empty? ? "—" : (capacity.nil? ? I18n.t("bundles.stock_unlimited") : capacity.to_s),
      price_cents: @price_cents, difference_cents: difference,
      difference: difference.nil? ? "—" : money(difference.abs), percentage: percentage,
      percentage_label: percentage.nil? ? nil : "#{percentage.abs}%",
      above_base: difference&.negative? || false,
      warning: total.nil? ? I18n.t("bundles.errors.component_price_missing") : nil
    }
  end

  private

  def money(cents)
    return "—" if cents.nil?
    Money.new(cents, @organisation.currency).format
  end

  def fail_with(key)
    raise InvalidComposition, I18n.t("bundles.errors.#{key}")
  end
end
