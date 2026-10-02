require "test_helper"

class Storefront::OrderCampaignProgressTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  test "cart progress excludes Molduras and shows campaigns separately" do
    org = Organisation.create!(name: "Campaign cart")
    customer = org.customers.create!(company_name: "Buyer", contact_name: "J", active: true)
    user = org.customer_users.create!(customer: customer, email: "progress@example.test", password: "password123", active: true)
    frames = org.categories.create!(name: "Molduras")
    campaign = org.order_discount_campaigns.build(name: "Outubro", priority: 1)
    campaign.configure_category_scopes(mode: "exclude", category_ids: [frames.id])
    campaign.save!
    org.order_discounts.create!(order_discount_campaign: campaign, min_order_amount_cents: 75000, discount_type: 'percentage', discount_value: 0.07)
    other = org.order_discount_campaigns.create!(name: "Especial", priority: 2)
    org.order_discounts.create!(order_discount_campaign: other, min_order_amount_cents: 50000, discount_type: 'percentage', discount_value: 0.1)
    silver = org.products.create!(name: "Prata", unit_price: 50000, published: true)
    frame = org.products.create!(name: "Moldura", unit_price: 50000, published: true)
    frame.categories = [frames]
    sign_in user
    [silver, frame].each do |product|
      post order_items_path(org.slug), params: { product_id: product.id, order_item: { quantity: 1 } }
    end
    get cart_path(org.slug)
    assert_response :success
    assert_select "[data-order-campaign-id='#{campaign.id}']" do
      assert_select ".text-muted", text: /Todos exceto: Molduras/
      assert_select ".small", text: /Faltam.*250.*artigos elegíveis/
      assert_select ".text-success", count: 0
    end
    assert_select "[data-order-campaign-id='#{other.id}'] .text-success", text: /Campanha aplicada/
    order = user.orders.draft.find_by!(organisation: org)
    order.order_items.each do |item|
      assert_select "[data-line-total-id='#{item.id}'][data-total-cents='45000']", count: 2
      assert_select "[data-line-total-id='#{item.id}'] [data-line-campaign-savings-cents='5000']", count: 2
    end

    silver.update!(unit_price: 80000)
    get cart_path(org.slug)
    assert_response :success
    eligible = order.order_items.find_by!(product: silver)
    excluded = order.order_items.find_by!(product: frame)
    assert_select "[data-line-total-id='#{eligible.id}'][data-total-cents='74400']", count: 2
    assert_select "[data-line-total-id='#{eligible.id}'] small", text: /56/, count: 2
    assert_select "td.text-end > .text-success.text-nowrap", text: /744.*\(-7%\)/
    assert_select "td.text-end > .text-decoration-line-through.d-block", text: /800/
    assert_select "[data-line-total-id='#{eligible.id}']", text: /Campanha/, count: 0
    assert_select "[data-line-total-id='#{excluded.id}'][data-total-cents='50000']", count: 2
    assert_select "[data-line-total-id='#{excluded.id}'] [data-line-campaign-savings-cents]", count: 0
  end
end
