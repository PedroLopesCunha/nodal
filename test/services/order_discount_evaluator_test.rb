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
    pricing = OrderLinePricing.new(@order)
    assert_equal 37200, pricing.line(@items.first).total.cents
    assert_equal 30000, pricing.line(@items.last).total.cents
    assert_equal 0, pricing.line(@items.last).campaign_savings.cents
    assert_equal 104400, @items.sum { |item| pricing.line(item).total.cents }
    assert_equal 110000, @order.total_amount.cents, "presentation must not deduct the campaign twice"
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
    pricing = OrderLinePricing.new(@order)
    assert_equal 2800, pricing.line(@items.first.reload).campaign_savings.cents
    assert_equal BigDecimal('0.07'), pricing.line(@items.first).campaign_percentage
  end

  test "old placed orders without scope snapshots are not reconstructed" do
    @order.update!(placed_at: Time.current)
    assert_nil @order.auto_discount_scope_snapshot
    assert_equal Money.new(0, "EUR"), @order.auto_order_discount_amount
    assert @order.order_items.all? { |item| item.auto_order_discount_amount_cents.nil? }
    assert_equal @items.first.total_price, OrderLinePricing.new(@order).line(@items.first).total
  end

  test "line display compounds product and campaign discounts on the existing base" do
    @tier.update!(min_order_amount_cents: 50000, discount_value: 0.12, stackable: true)
    ProductDiscount.create!(organisation: @org, product: @items.first.product,
      discount_type: 'percentage', discount_value: 0.1, stackable: true)
    @order.refresh_cart!
    @order.order_items.reset
    pricing = OrderLinePricing.new(@order).line(@items.first.reload)
    assert_equal 40000, pricing.original_total.cents
    assert_equal 4320, pricing.campaign_savings.cents
    assert_equal 31680, pricing.total.cents
    assert_equal 36000, @items.first.total_price.cents
  end

  test 'exclusive campaign replaces inferior line discount without changing qualification' do
    ProductDiscount.create!(organisation: @org, product: @items.first.product,
      discount_type: 'percentage', discount_value: 0.05, stackable: false)
    @tier.update!(discount_value: 0.12)
    @order.refresh_cart!
    result = @order.automatic_discount_evaluation
    assert_equal 78000, result.qualification_cents
    assert_equal 2000, result.replaced_line_savings[@items.first.id]
    assert_equal 2800, result.allocations[@items.first.id]
    assert_equal 35200, @items.first.reload.total_price.cents - result.allocations[@items.first.id]
    assert_equal 100400, @order.total_with_auto_discount.cents
    pricing = OrderLinePricing.new(@order)
    assert_equal 0, pricing.line(@items.first).line_discount_percentage
    assert_equal 4800, pricing.line(@items.first).campaign_savings.cents
    assert_equal 0, pricing.line_discount_amount.cents
    assert_equal 9600, pricing.campaign_discount_amount.cents
    assert_equal 110000, pricing.subtotal_before_campaign.cents
  end

  test 'both rules must consent to accumulation and stronger line prices survive' do
    rule = ProductDiscount.create!(organisation: @org, product: @items.first.product,
      discount_type: 'percentage', discount_value: 0.05, stackable: true)
    @tier.update!(discount_value: 0.12)
    @order.refresh_cart!
    assert_equal 2000, @order.automatic_discount_evaluation.replaced_line_savings[@items.first.id]
    rule.update!(stackable: false)
    @tier.update!(stackable: true)
    @order.refresh_cart!
    assert_equal 2000, @order.automatic_discount_evaluation.replaced_line_savings[@items.first.id]
    rule.update!(discount_value: 0.20)
    @tier.update!(min_order_amount_cents: 50000)
    @order.refresh_cart!
    assert_equal 0, @order.automatic_discount_evaluation.allocations.fetch(@items.first.id, 0)
    assert_not @order.automatic_discount_evaluation.replaced_line_savings.key?(@items.first.id)
  end

  test 'a threshold is not unlocked by removing a line discount' do
    ProductDiscount.create!(organisation: @org, product: @items.first.product,
      discount_type: 'percentage', discount_value: 0.05)
    @tier.update!(min_order_amount_cents: 79000, discount_value: 0.12)
    @order.refresh_cart!
    assert_nil @order.automatic_discount_evaluation
  end

  test 'replacement snapshots preserve final prices and qualification after rule edits' do
    rule = ProductDiscount.create!(organisation: @org, product: @items.first.product,
      discount_type: 'percentage', discount_value: 0.05)
    @tier.update!(discount_value: 0.12)
    @order.refresh_cart!
    @order.terms_accepted_at = Time.current
    @order.finalize_checkout!
    assert_equal 78000, @order.auto_discount_scope_snapshot['qualification_cents']
    assert_equal 'mutual_stackability_per_line_v1', @order.auto_discount_scope_snapshot['competition_policy']
    assert_equal 7600, @order.auto_discount_amount_cents
    rule.update!(discount_value: 0.5, stackable: true)
    @tier.update!(discount_value: 0.9, stackable: true)
    @order.reload
    pricing = OrderLinePricing.new(@order)
    assert_equal 35200, pricing.line(@items.first.reload).total.cents
    assert_equal 4800, pricing.line(@items.first).campaign_savings.cents
    assert_equal 9600, pricing.campaign_discount_amount.cents
    assert_equal 100400, @order.total_with_auto_discount.cents
  end

  test 'fixed campaigns compare allocated money and never redistribute losing shares' do
    ProductDiscount.create!(organisation: @org, product: @items.first.product,
      discount_type: 'percentage', discount_value: 0.20)
    @tier.update!(min_order_amount_cents: 50000, discount_type: 'fixed', discount_value: 80)
    @order.refresh_cart!
    result = @order.automatic_discount_evaluation
    assert_equal 0, result.allocations.fetch(@items.first.id, 0)
    assert_equal 2000, result.allocations[@items[1].id]
    assert_equal 2000, result.allocations[@items[2].id]
    assert_equal 98000, @order.total_with_auto_discount.cents
  end

  test 'ties keep line prices and do not announce a campaign saving' do
    @items.first.update_columns(discount_percentage: 0.07)
    @tier.update!(min_order_amount_cents: 50000)
    result = @order.automatic_discount_evaluation
    assert_equal 0, result.allocations.fetch(@items.first.id, 0)
    assert_equal 0, OrderLinePricing.new(@order).line(@items.first.reload).campaign_savings.cents
  end

  test 'the 1100 euro cart receives 12 percent instead of 5 plus 12' do
    [50000, 20000, 40000, 0].each_with_index { |price, i| @items[i].product.update!(unit_price: price) }
    rule = @org.product_discounts.build(discount_type: 'percentage', discount_value: 0.05, min_quantity: 1)
    rule.configure_category_scopes(mode: 'all')
    rule.save!
    @tier.update!(min_order_amount_cents: 100000, discount_value: 0.12)
    @order.refresh_cart!
    assert_equal 104500, @order.automatic_discount_evaluation.qualification_cents
    pricing = OrderLinePricing.new(@order)
    assert_equal [44000, 17600, 35200, 0], @items.map { |item| pricing.line(item.reload).total.cents }
    assert_equal 96800, @order.total_with_auto_discount.cents
    assert_equal 13200, pricing.campaign_discount_amount.cents
    assert_equal 0, pricing.line_discount_amount.cents
    assert_empty CartDiscountNudges.new(@order).unlocked
  end

  test 'customer category prices compete and excluded lines keep their price' do
    rule = @org.customer_product_discounts.build(customer: @order.customer,
      discount_type: 'percentage', discount_value: 0.05, min_quantity: 1)
    rule.configure_category_scopes(mode: 'all')
    rule.save!
    @tier.update!(min_order_amount_cents: 50000, discount_value: 0.12)
    @order.refresh_cart!
    pricing = OrderLinePricing.new(@order)
    assert_equal 35200, pricing.line(@items.first.reload).total.cents
    assert_equal 28500, pricing.line(@items.last.reload).total.cents
    assert_equal 1500, pricing.line_discount_amount.cents
  end

  test 'old allocation snapshots preserve historical stacking despite current exclusivity' do
    @items.first.update_columns(discount_percentage: 0.05, auto_order_discount_amount_cents: 4560)
    @items[1].update_column(:auto_order_discount_amount_cents, 2400)
    @items[2].update_column(:auto_order_discount_amount_cents, 2400)
    @items.last.update_column(:auto_order_discount_amount_cents, 0)
    @order.update!(placed_at: Time.current, auto_discount_type: 'percentage', auto_discount_value: 0.12,
      auto_discount_amount_cents: 9360, auto_discount_scope_snapshot: { campaign_id: @campaign.id })
    pricing = OrderLinePricing.new(@order.reload)
    assert_equal 33440, pricing.line(@items.first.reload).total.cents
    assert_equal BigDecimal('0.05'), pricing.line(@items.first).line_discount_percentage
    assert_equal 4560, pricing.line(@items.first).campaign_savings.cents
    assert_equal 98640, @order.total_with_auto_discount.cents
  end

  test "fixed campaign line display retains exact cent allocations and shows no percentage" do
    @tier.update!(discount_type: 'fixed', discount_value: 0.01)
    pricing = OrderLinePricing.new(@order)
    assert_equal 1, @items.sum { |item| pricing.line(item).campaign_savings.cents }
    assert_nil pricing.line(@items.first).campaign_percentage
    assert_equal 109999, @items.sum { |item| pricing.line(item).total.cents }
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
