require "test_helper"

class MultiCategoryDiscountsTest < ActiveSupport::TestCase
  def setup
    @org = Organisation.create!(name: "Multi")
    @customer = Customer.create!(organisation: @org, company_name: "Buyer", contact_name: "J", active: true)
    @categories = %w[Silver Bilaminado Molduras].map { |name| Category.create!(organisation: @org, name: name) }
    @products = [30000, 25000, 40000].each_with_index.map do |price, i|
      product = Product.create!(organisation: @org, name: "Product #{i}", unit_price: price)
      product.categories = [@categories[i]]
      product
    end
    user = CustomerUser.create!(organisation: @org, customer: @customer, email: "multi@example.test",
      password: "password123", contact_name: "J", active: true)
    @order = Order.create!(organisation: @org, customer: @customer, customer_user: user)
    @products.each { |product| @order.order_items.create!(product: product, quantity: 1) }
  end

  def calculator(product)
    DiscountCalculator.new(product: product, customer: @customer, quantity: 1,
      cart_context: CartDiscountContext.new(@order.order_items.reload.to_a))
  end

  def rule(model = ProductDiscount, mode: "include", ids: @categories.first(2).map(&:id))
    attributes = { organisation: @org, discount_type: "percentage", discount_value: 0.08,
      condition_type: "amount", condition_scope: "summed", min_amount_cents: 50000 }
    attributes[:customer] = @customer if model == CustomerProductDiscount
    discount = model.new(attributes)
    discount.configure_category_scopes(mode: mode, category_ids: ids)
    discount.save!
    discount
  end

  test "combined categories unlock one discount and unrelated products stay unchanged" do
    rule
    assert_equal Money.new(27600, "EUR"), calculator(@products.first).final_price
    assert_equal Money.new(23000, "EUR"), calculator(@products.second).final_price
    assert_equal Money.new(40000, "EUR"), calculator(@products.third).final_price
    @products.second.default_variant.update!(unit_price_cents: 15000)
    @order.reload.refresh_cart!
    assert_equal 0, @order.order_items.first.discount_percentage
  end

  test "overlapping categories do not double count or double apply stackable rules" do
    @products.first.categories << @categories.second
    discount = rule
    discount.update!(stackable: true, min_amount_cents: 70000)
    assert_equal @products.first.price, calculator(@products.first).final_price
    discount.update!(min_amount_cents: 50000)
    assert_equal 1, calculator(@products.first).all_discounts.size
    assert_equal Money.new(27600, "EUR"), calculator(@products.first).final_price
  end

  test "customer category scope uses the same aggregate engine" do
    rule(CustomerProductDiscount)
    assert_equal Money.new(27600, "EUR"), calculator(@products.first).final_price
  end

  test "exclude scopes omit excluded articles from qualification and application" do
    rule(mode: "exclude", ids: [@categories.last.id])
    assert_equal Money.new(27600, "EUR"), calculator(@products.first).final_price
    assert_equal @products.last.price, calculator(@products.last).final_price
  end

  test "legacy category changes keep the adapter in sync" do
    discount = ProductDiscount.create!(organisation: @org, category: @categories.first,
      discount_type: "percentage", discount_value: 0.1)
    discount.reload.update!(category: @categories.last)
    assert_equal [@categories.last.id], discount.reload.discount_scope.selected_category_ids
  end
  test "nudges aggregate the rule once across all eligible categories" do
    discount = rule
    discount.update!(min_amount_cents: 60000)
    opportunities = CartDiscountNudges.new(@order).opportunities
    assert_equal 1, opportunities.size
    assert_equal Money.new(5000, "EUR"), opportunities.first.remaining
    assert_empty CartDiscountNudges.new(@order).unlocked
  end

  test "campaign catalog respects exclude scopes" do
    rule(mode: "exclude", ids: [@categories.last.id])
    assert_equal @products.first(2).map(&:id).sort, @org.products.on_promotion.pluck(:id).sort
  end

end
