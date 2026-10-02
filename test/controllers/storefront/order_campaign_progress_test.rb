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
  end
end
