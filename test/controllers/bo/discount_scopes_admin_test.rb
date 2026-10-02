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
end
