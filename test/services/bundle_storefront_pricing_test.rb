require "test_helper"

class BundleStorefrontPricingTest < ActiveSupport::TestCase
  setup do
    @org = Organisation.create!(name: "Bundle viewer prices", currency: "EUR")
    category = @org.categories.create!(name: "Silver")
    @products = [1200, 2300, 1200].each_with_index.map { |price, i|
      @org.products.create!(name: "Component #{i}", unit_price: price, published: true)
    }
    [@products.first, @products.last].each { |product| product.categories << category }
    @org.product_discounts.create!(category: category, discount_type: "percentage", discount_value: 0.05)
    @bundle = @org.products.create!(name: "Seven units", bundle: true, published: true, unit_price: 9900,
      bundle_components_attributes: @products.zip([2, 3, 2]).map { |product, quantity| { product_variant_id: product.default_variant.id, quantity: quantity } })
    @customer = @org.customers.create!(company_name: "Pedro", contact_name: "Pedro", active: true, erp_discount_percentage: 20)
  end

  test "member sees 117 base value even when public discounts and a customer are present" do
    prices = BundleStorefrontPricing.new(product: @bundle, customer: @customer, base_prices: true).call
    assert_equal 11700, prices[:separate].cents
    assert_equal 9900, prices[:price].cents
    assert_equal 1800, prices[:savings].cents
    assert_equal [BigDecimal("12"), BigDecimal("23"), BigDecimal("12")], prices[:lines].map { |line| line[:separate_unit] }
  end

  test "public customer prices explain the original 114.60 comparison" do
    prices = BundleStorefrontPricing.new(product: @bundle).call
    assert_equal 11460, prices[:separate].cents
    assert_equal 1560, prices[:savings].cents
  end

  test "included unit prices share the cart allocation and preserve fractional cents" do
    prices = BundleStorefrontPricing.new(product: @bundle, base_prices: true).call
    assert_equal [2031, 5838, 2031], prices[:lines].map { |line| line[:bundle_total].cents }
    assert_equal [BigDecimal("10.155"), BigDecimal("19.46"), BigDecimal("10.155")], prices[:lines].map { |line| line[:bundle_unit] }
    user = @customer.customer_users.create!(organisation: @org, email: "bundle-prices@example.com", password: "password123", active: true)
    order = @org.orders.create!(customer: @customer, customer_user: user)
    group = BundleCartService.new(order).add!(@bundle, 1)
    assert_equal prices[:lines].map { |line| line[:bundle_total].cents }, group.order_items.order(:id).pluck(:bundle_amount_cents)
    customer_prices = BundleStorefrontPricing.new(product: @bundle, customer: @customer).call
    assert_equal 9168, customer_prices[:separate].cents
    assert_equal 7920, customer_prices[:price].cents
    assert_equal customer_prices[:price].cents, group.order_items.sum { |item| OrderLinePricing.new(order).line(item).total.cents }
  end

  test "does not claim savings when individual purchases are cheaper" do
    @bundle.update!(unit_price: 15000)
    prices = BundleStorefrontPricing.new(product: @bundle).call
    assert_equal 0, prices[:savings].cents
    assert_equal 15000, prices[:price].cents
  end
end
