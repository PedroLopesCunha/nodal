require "test_helper"

class DiscountScopesAdminTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def setup
    @org = Organisation.create!(name: "Admin scope")
    member = Member.create!(email: "scopeadmin@example.test", password: "password123", first_name: "J", last_name: "Admin")
    OrgMember.create!(organisation: @org, member: member, role: "owner", active: true)
    sign_in member
    @category = Category.create!(organisation: @org, name: "Molduras")
    @previous_enabled = Rails.configuration.x.discount_category_scopes_enabled
    Rails.configuration.x.discount_category_scopes_enabled = true
  end

  def teardown
    Rails.configuration.x.discount_category_scopes_enabled = @previous_enabled
  end

  test "campaign UI explains priority and creates equal scopes" do
    get new_bo_order_discount_campaign_path(@org.slug)
    assert_response :success
    assert_select "label", text: "Prioridade — 1 é a mais alta"
    post bo_order_discount_campaigns_path(@org.slug), params: {
      order_discount_campaign: { name: "Outubro", priority: 1 },
      scope_config: { mode: "exclude", category_ids: [@category.id] }
    }
    assert_response :redirect
    campaign = @org.order_discount_campaigns.last
    assert_equal ["exclude", [@category.id]], campaign.qualification_scope.signature
    assert_equal campaign.qualification_scope.signature, campaign.discount_scope.signature
    get bo_pricing_path(@org.slug, tab: 'order_tiers')
    assert_response :success
    assert_select "strong", text: "Outubro"
  end

  test "failed campaign edit rolls back scope changes" do
    campaign = @org.order_discount_campaigns.create!(name: "Outubro", priority: 1)
    patch bo_order_discount_campaign_path(@org.slug, campaign), params: {
      order_discount_campaign: { name: "", priority: 1 },
      scope_config: { mode: "exclude", category_ids: [@category.id] }
    }
    assert_response :unprocessable_entity
    assert_equal ["all", []], campaign.reload.discount_scope.signature
  end

  test "product admin creates a named multicategory rule and renders it for editing" do
    other = Category.create!(organisation: @org, name: "Prata")
    post bo_product_discounts_path(@org.slug), params: {
      target_type: 'category', scope_config: { mode: 'include', category_ids: [@category.id, other.id] },
      product_discount: { name: 'Outubro prata', discount_type: 'percentage', discount_value: '0.08',
        condition_type: 'amount', condition_scope: 'summed', min_amount: '500' }
    }
    assert_response :redirect
    rule = @org.product_discounts.last
    assert_equal 'Outubro prata', rule.name
    assert_equal rule.qualification_scope.signature, rule.discount_scope.signature
    get edit_bo_product_discount_path(@org.slug, rule)
    assert_response :success
    assert_select "select[name='scope_config[category_ids][]'][multiple]"
  end

  test "foreign category IDs cannot create or alter campaigns" do
    foreign = Organisation.create!(name: "Foreign")
    category = Category.create!(organisation: foreign, name: "Foreign")
    assert_no_difference 'OrderDiscountCampaign.count' do
      post bo_order_discount_campaigns_path(@org.slug), params: {
        order_discount_campaign: { name: "Invalid", priority: 1 },
        scope_config: { mode: "include", category_ids: [category.id] }
      }
    end
    assert_response :unprocessable_entity
  end
  test "deleting a used tier preserves the order and explains deactivation" do
    tier = @org.order_discounts.create!(min_order_amount_cents: 75000,
      discount_type: 'percentage', discount_value: 0.07)
    customer = @org.customers.create!(company_name: 'Buyer', contact_name: 'J', active: true)
    user = @org.customer_users.create!(customer: customer, email: 'tier-history@example.test',
      password: 'password123', active: true)
    order = @org.orders.create!(customer: customer, customer_user: user, order_discount: tier,
      placed_at: Time.current, auto_discount_type: 'percentage', auto_discount_value: 0.07,
      auto_discount_amount_cents: 5600)
    notification = DiscountEmailNotification.create!(organisation: @org, notifiable: tier,
      status: 'pending', recipient_count: 0)
    assert_no_difference ['OrderDiscount.count', 'Order.count', 'DiscountEmailNotification.count'] do
      delete bo_order_discount_path(@org.slug, tier)
    end
    assert_redirected_to bo_pricing_path(@org.slug, tab: 'order_tiers')
    assert_match(/Desative/, flash[:alert])
    assert_equal tier.id, order.reload.order_discount_id
    assert_equal 5600, order.auto_discount_amount_cents
    assert tier.reload.active?
    assert DiscountEmailNotification.exists?(notification.id)
    patch toggle_active_bo_order_discount_path(@org.slug, tier)
    assert_response :redirect
    assert_not tier.reload.active?
    assert_equal 5600, order.reload.auto_discount_amount_cents
  end

  test "unused tiers can still be deleted" do
    tier = @org.order_discounts.create!(min_order_amount_cents: 75000,
      discount_type: 'percentage', discount_value: 0.07)
    assert_difference 'OrderDiscount.count', -1 do
      delete bo_order_discount_path(@org.slug, tier)
    end
    assert_redirected_to bo_pricing_path(@org.slug, tab: 'order_tiers')
    assert_nil flash[:alert]
  end

  test 'both variant endpoints paginate category scopes and search SKUs' do
    child = @org.categories.create!(name: 'Child', ancestry: @category.id.to_s)
    products = 52.times.map do |i|
      product = @org.products.create!(name: "Page #{i.to_s.rjust(3, '0')}", sku: "PAGE-#{i}", unit_price: 1000)
      product.categories = [child, @category]
      product
    end
    [variant_overrides_bo_product_discounts_path(@org.slug), variant_overrides_bo_customer_product_discounts_path(@org.slug)].each do |path|
      get path, params: { scope_mode: 'include', category_ids: [@category.id, child.id] }
      assert_response :success
      assert_select '[data-discount-preview-target=row]', count: 50
      assert_select 'button[data-page="2"]', count: 1
      get path, params: { scope_mode: 'include', category_ids: [@category.id], variant_page: 2 }
      assert_select '[data-discount-preview-target=row]', count: 2
      get path, params: { scope_mode: 'include', category_ids: [@category.id], variant_query: 'PAGE-51' }
      assert_select '[data-discount-preview-target=row]', count: 1
      get path, params: { scope_mode: 'exclude', category_ids: [@category.id] }
      assert_select '[data-discount-preview-target=row]', count: 0
    end
  end

  test 'saving a rule persists submitted variant edits from multiple pages' do
    products = 2.times.map { |i| @org.products.create!(name: "Edited #{i}", unit_price: 1000) }
    first, second = products.map { |product| product.product_variants.first }
    post bo_product_discounts_path(@org.slug), params: {
      target_type: 'category', scope_config: { mode: 'all' },
      product_discount: { discount_type: 'percentage', discount_value: '0.08' },
      variant_overrides: {
        first.id => { exclude_from_discounts: '1', custom_discount_type: '', custom_discount_value: '' },
        second.id => { exclude_from_discounts: '0', custom_discount_type: 'percentage', custom_discount_value: '0.15' }
      }
    }
    assert_response :redirect
    assert first.reload.exclude_from_discounts?
    assert_equal BigDecimal('0.15'), second.reload.custom_discount_value
  end

end
