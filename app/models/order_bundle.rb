class OrderBundle < ApplicationRecord
  belongs_to :order
  belongs_to :product
  has_many :order_items, dependent: :destroy
  monetize :unit_price_cents, as: :price
  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :unit_price_cents, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate do
    errors.add(:product, :invalid) unless product&.bundle? && product.organisation_id == order&.organisation_id
  end

  def customer_total(pricing = OrderLinePricing.new(order))
    order_items.sum(Money.new(0, order.organisation.currency)) { |item| pricing.line(item).total }
  end

  def total_price
    price * quantity
  end

  def capacity_in_cart
    return 0 unless product.bundle_purchasable? && current_composition?
    order_items.map do |item|
      variant = item.product_variant
      next 0 unless variant&.published? && variant.product.published? && variant.purchasable?
      next Float::INFINITY if variant.sells_without_stock?
      others = order.order_items.where(product_variant_id: variant.id)
        .where("order_bundle_id IS NULL OR order_bundle_id != ?", id).sum(:quantity)
      [(variant.stock_quantity.to_i - others) / item.bundle_component_quantity, 0].max
    end.min || 0
  end

  def current_composition?
    return true if order.placed?
    current = product.bundle_components.map { |part| [part.product_variant_id, part.quantity] }.sort
    saved = composition.map { |part| [part["variant_id"], part["quantity"]] }.sort
    current == saved
  end
end
