# Aggregates the cart's quantity and € value per product and per category,
# so the DiscountCalculator can evaluate "summed" discount conditions (a
# threshold met across a product's variants, or across a whole category).
# Category totals cascade up the tree (a line in a subcategory counts toward
# its ancestor categories).
class CartDiscountContext
  def initialize(order_items)
    @product_qty = Hash.new(0)
    @product_amount = Hash.new(0)
    @category_qty = Hash.new(0)
    @category_amount = Hash.new(0)

    order_items.each { |item| add_item(item) }
  end

  def product_quantity(product_id) = @product_qty[product_id]
  def product_amount_cents(product_id) = @product_amount[product_id]
  def category_quantity(category_id) = @category_qty[category_id]
  def category_amount_cents(category_id) = @category_amount[category_id]

  private

  def add_item(item)
    product = item.product
    return unless product

    qty = item.quantity.to_i
    amount = (item.price * qty).cents # base line value, before discount

    @product_qty[product.id] += qty
    @product_amount[product.id] += amount

    product.categories.flat_map(&:path_ids).uniq.each do |category_id|
      @category_qty[category_id] += qty
      @category_amount[category_id] += amount
    end
  end
end
