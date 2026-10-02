require "test_helper"

class OrderDiscountEvaluatorTest < ActiveSupport::TestCase
  def setup
    @org = Organisation.create!(name: "Order scopes")
    customer = Customer.create!(organisation: @org, company_name: "Buyer", contact_name: "J", active: true)
    user = CustomerUser.create!(organisation: @org, customer: customer, email: "orderscope@test.example", password: "password123", contact_name: "J", active: true)
    @order = Order.create!(organisation: @org, customer: customer, customer_user: user)
    @frames = Category.create!(organisation: @org, name: "Molduras")
    @items = [40000, 20000, 20000, 30000].each_with_index.map do |price, i|
      product = Product.create!(organisation: @org, name: "Product #{i}", unit_price: price, published: true)
      product.categories = [@frames] if i == 3
      @order.order_items.create!(product: product, quantity: 1)
    end
    @campaign = OrderDiscountCampaign.new(organisation: @org, name: "Outubro", priority: 1)
    @campaign.configure_category_scopes(mode: "exclude", category_ids: [@frames.id])
    @campaign.save!
    @tier = tier(@campaign, 75000, 0.07)
  end

  def tier(campaign, minimum, value)
    OrderDiscount.create!(organisation: @org, order_discount_campaign: campaign,
      min_order_amount_cents: minimum, discount_type: "percentage", discount_value: value)
  end

  test "excluded categories neither qualify nor receive the order discount" do
    result = @order.automatic_discount_evaluation
    assert_equal 80000, result.qualification_cents
    assert_equal 80000, result.discount_base_cents
    assert_equal Money.new(5600, "EUR"), result.discount_amount
    assert_not result.allocations.key?(@items.last.id)
    assert_equal 5600, result.allocations.values.sum
    assert_equal Money.new(104400, "EUR"), @order.total_with_auto_discount
  end

  test "a large excluded subtotal cannot unlock a campaign" do
    @items[0].update!(unit_price: 30000)
    @items[2].destroy!
    @items[3].update!(unit_price: 50000)
    @order.order_items.reset
    assert_nil @order.best_order_discount
    assert_equal Money.new(0, "EUR"), @order.auto_order_discount_amount
  end

  test "priority wins over savings and the highest reached tier wins within a campaign" do
    other = OrderDiscountCampaign.create!(organisation: @org, name: "Other", priority: 2)
    tier(other, 10000, 0.50)
    assert_equal @tier, @order.best_order_discount
    upper = tier(@campaign, 80000, 0.08)
    assert_equal upper, @order.best_order_discount
    upper.update!(active: false)
    assert_equal @tier, @order.best_order_discount
    @tier.update!(active: false)
    assert_equal other, @order.best_order_discount.order_discount_campaign
  end

  test "order qualification uses values after line discounts while product thresholds use base values" do
    ProductDiscount.create!(organisation: @org, product: @items.first.product,
      discount_type: "percentage", discount_value: 0.5, condition_type: "amount", min_amount_cents: 40000)
    @order.reload.refresh_cart!
    assert_equal 0.5, @items.first.reload.discount_percentage
    assert_nil @order.best_order_discount
  end

  test "fixed discount is capped and allocation reconciles exactly" do
    @tier.update!(discount_type: "fixed", discount_value: 1000)
    result = @order.automatic_discount_evaluation
    assert_equal 80000, result.discount_amount.cents
    assert_equal 80000, result.allocations.values.sum
  end

  test "qualification and application bases remain independent" do
    @campaign.discount_scope.categories = []
    @campaign.discount_scope.update!(mode: "all")
    result = @order.automatic_discount_evaluation
    assert_equal 80000, result.qualification_cents
    assert_equal 110000, result.discount_base_cents
    assert_equal 7700, result.discount_amount.cents
  end

  test "checkout snapshots allocations and subsequent campaign edits cannot rewrite history" do
    @order.terms_accepted_at = Time.current
    @order.finalize_checkout!
    assert_equal 5600, @order.auto_discount_amount_cents
    assert_equal 5600, @order.order_items.sum(:auto_order_discount_amount_cents)
    assert_equal 0, @items.last.reload.auto_order_discount_amount_cents
    snapshot = @order.auto_discount_scope_snapshot.deep_dup
    @tier.update!(discount_value: 0.5)
    @campaign.update!(name: "Changed")
    assert_equal Money.new(5600, "EUR"), @order.reload.auto_order_discount_amount
    assert_equal snapshot, @order.auto_discount_scope_snapshot
  end

  test "old placed orders without scope snapshots are not reconstructed" do
    @order.update!(placed_at: Time.current)
    assert_nil @order.auto_discount_scope_snapshot
    assert_equal Money.new(0, "EUR"), @order.auto_order_discount_amount
    assert @order.order_items.all? { |item| item.auto_order_discount_amount_cents.nil? }
  end

  test "new campaigns reject overlapping duplicate minimums and foreign owners" do
    duplicate = @tier.dup
    assert_not duplicate.valid?
    foreign = Organisation.create!(name: "Foreign")
    duplicate.organisation = foreign
    assert_not duplicate.valid?
    assert duplicate.errors[:order_discount_campaign].any?
  end
end
