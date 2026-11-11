require 'test_helper'
require 'minitest/mock'

class Storefront::ErpCustomerDiscountTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @org = Organisation.create!(name: 'ERP storefront', currency: 'EUR', tax_rate: 0.23,
      email_order_confirmation_enabled: true, free_shipping_threshold_cents: 8000)
    @customer = @org.customers.create!(company_name: 'Buyer', contact_name: 'Ana', active: true,
      erp_discount_percentage: 20)
    @user = @org.customer_users.create!(customer: @customer, email: 'erp-store@example.test',
      password: 'password123', active: true, invitation_accepted_at: Time.current)
    @product = @org.products.create!(name: 'ERP Article', sku: 'ERP-ARTICLE', unit_price: 10000, published: true)
    sign_in @user
  end

  test 'cards show the customer price without an ERP promotion badge or empty discount panel' do
    get products_path(@org.slug)
    assert_response :success
    assert_select '.product-card-price-original', text: /100/
    assert_select '.product-card-price-discounted', text: /80/
    assert_select '.product-card-discount-badge', count: 0
    assert_select '.product-card-prices', text: /desconto de cliente|customer discount/, count: 0
    get product_path(@org.slug, @product)
    assert_response :success
    assert_select '[data-product-pricing-target="headerPrice"]', text: /80/
    assert_select 'em', text: I18n.t('erp_discount.included', percentage: '20%')
    assert_select '.alert-heading', text: I18n.t('storefront.products.show.available_discounts'), count: 0
  end

  test 'variable cards keep both ranges as separate rows of complete amounts' do
    variable = @org.products.create!(name: 'Variable article', has_variants: true, published: true)
    [125050, 999999].each_with_index do |cents, index|
      variable.product_variants.create!(organisation: @org, name: "Size #{index}", sku: "ERP-SIZE-#{index}",
        unit_price_cents: cents, unit_price_currency: 'EUR', published: true, available: true, is_default: false)
    end
    get products_path(@org.slug)
    assert_response :success
    assert_select 'a[href=?]', product_path(@org.slug, variable) do
      assert_select '.product-card-prices > .product-card-price-original .product-card-price-amount', count: 2
      assert_select '.product-card-prices > .product-card-price-discounted .product-card-price-amount', count: 2
      assert_select '.product-card-price-original', text: /1[.,]250|1250/
      assert_select '.product-card-price-discounted', text: /1[.,]000|1000/
    end
  end

  test 'cart checkout history email and PDF retain the same customer price' do
    @org.product_discounts.create!(product: @product, discount_type: 'percentage', discount_value: 0.1)
    post order_items_path(@org.slug), params: { product_id: @product.id, order_item: { quantity: 1 } }
    order = @user.orders.draft.find_by!(organisation: @org)
    item = order.order_items.first
    get cart_path(@org.slug)
    assert_response :success
    assert_select "[data-line-total-id='#{item.id}'][data-total-cents='7200']", count: 2
    get checkout_path(@org.slug)
    assert_response :success
    assert_select '[data-checkout-subtotal-value="7200"][data-checkout-free-shipping-subtotal-value="7200"]'
    assert_select '[data-checkout-tax-value="1656"]'
    assert_select "[data-line-total-id='#{item.id}'][data-total-cents='7200']"

    order.terms_accepted_at = Time.current
    order.finalize_checkout!
    @customer.update!(erp_discount_percentage: 50)
    get order_path(@org.slug, order)
    assert_response :success
    assert_select "[data-line-total-id='#{item.id}'][data-total-cents='7200']"
    mail = CustomerMailer.with(customer_user: @user, order: order.reload).confirm_order
    [mail.html_part, mail.text_part].each do |part|
      assert_includes part.body.decoded, Money.new(7200, 'EUR').format
      assert_includes part.body.decoded, I18n.t('erp_discount.label')
    end
    captured = nil
    fake = Object.new
    def fake.to_pdf = '%PDF-1.4'
    Grover.stub :new, ->(html) { captured = html; fake } do
      get download_pdf_order_path(@org.slug, order)
    end
    assert_response :success
    assert_includes captured, I18n.t('erp_discount.label')
    assert_match(/72/, Nokogiri::HTML(captured).at_css('tbody td.fw-bold .text-success').text)
  end
end
