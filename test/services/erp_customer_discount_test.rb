require 'test_helper'
require 'minitest/mock'

class ErpCustomerDiscountTest < ActiveSupport::TestCase
  setup do
    @org = Organisation.create!(name: 'ERP customer pricing', currency: 'EUR', tax_rate: 0.23)
    @customer = @org.customers.create!(company_name: 'Buyer', contact_name: 'Ana', active: true,
      erp_discount_percentage: 20, external_id: 'C-ERP')
    @user = @customer.customer_users.create!(organisation: @org, contact_name: 'Ana',
      email: 'erp-discount@example.test', password: 'password123')
    @product = @org.products.create!(name: 'Article', sku: 'ERP-ARTICLE', unit_price: 10000, published: true)
    @rule = @org.product_discounts.create!(product: @product, discount_type: 'percentage', discount_value: 0.1)
    @order = @org.orders.create!(customer: @customer, customer_user: @user)
    @item = @order.order_items.create!(product: @product, quantity: 1)
  end

  test 'catalogue shows both discounts while internal line prices retain Nodal only' do
    calc = DiscountCalculator.new(product: @product, customer: @customer)
    assert_equal 7200, calc.final_price.cents
    assert_equal BigDecimal('0.28'), calc.effective_discount[:percentage]
    assert_equal 20, calc.discount_breakdown[:erp_discount_percentage]
    assert_equal [:product], calc.applied_discounts.map { |d| d[:type] }
    assert_equal BigDecimal('0.1'), @item.discount_percentage
    assert_equal 9000, @item.total_price.cents
    assert_equal 7200, OrderLinePricing.new(@order).line(@item).total.cents
    assert_equal 7200, @order.cart_subtotal.cents
    assert_equal 7200, @order.subtotal_after_discount.cents
    assert_equal 1656, @order.calculated_tax.cents
  end

  test 'ERP-only price is not a promotion and respects variants and anonymous browsing' do
    @rule.destroy!
    @product.default_variant.update!(unit_price_cents: 12500)
    calc = DiscountCalculator.new(product: @product, customer: @customer, variant: @product.default_variant)
    assert_equal 10000, calc.final_price.cents
    assert calc.discount_breakdown[:has_discount]
    assert_empty calc.applied_discounts
    assert_equal 12500, DiscountCalculator.new(product: @product, variant: @product.default_variant).final_price.cents
  end

  test 'ERP discount applies after a fixed Nodal campaign without competing with it' do
    @org.order_discounts.create!(min_order_amount_cents: 8000, discount_type: 'fixed', discount_value: 15,
      stackable: true)
    @rule.update!(stackable: true)
    assert_equal 1500, @order.auto_order_discount_amount.cents
    assert_equal 7500, @order.total_with_auto_discount.cents
    assert_equal 6000, @order.cart_subtotal.cents
    assert_equal 6000, @order.subtotal_after_discount.cents
  end

  test 'ERP rounding reconciles per line rather than rounding the whole order' do
    @rule.destroy!
    @product.default_variant.update!(unit_price_cents: 3)
    @customer.update!(erp_discount_percentage: 50)
    @order.order_items.create!(product: @product, quantity: 1, note: 'second line')
    @order.refresh_cart!
    assert_equal 2, @order.cart_subtotal.cents
    assert_equal 2, @order.subtotal_after_discount.cents
    assert_equal 4, @order.erp_discount_amount.cents
  end

  test 'checkout freezes ERP percentage and prices across customer updates' do
    @order.terms_accepted_at = Time.current
    @order.finalize_checkout!
    assert_equal 20, @order.reload.erp_discount_percentage
    @customer.update!(erp_discount_percentage: 50)
    @rule.update!(discount_value: 0.8)
    @order.reload
    assert_equal 7200, @order.subtotal_after_discount.cents
    assert_equal 7200, OrderLinePricing.new(@order).line(@item.reload).total.cents
    assert_equal 1656, @order.tax_amount.cents
  end

  test 'old orders default to no ERP discount regardless of current customer terms' do
    @order.update_columns(placed_at: Time.current, erp_discount_percentage: 0)
    @order.reload
    assert_equal 9000, @order.subtotal_after_discount.cents
    assert_equal 9000, OrderLinePricing.new(@order).line(@item).total.cents
  end

  test 'ERP-only changes trigger the existing cart confirmation policy' do
    @order.refresh_cart!
    @order.update_column(:pricing_changed_at, nil)
    @org.update!(cart_price_change_policy: 'confirm')
    @customer.update!(erp_discount_percentage: 30)
    changes = @order.refresh_cart!
    assert_includes changes[:discount_changed], @item.id
    assert @order.reload.pricing_changed_at
    assert_equal 6300, @order.cart_subtotal.cents
  end

  test 'Nodal cap is independent of the ERP-owned condition' do
    @org.update!(max_discount_percentage: 0.05)
    assert_equal 9500, @order.nodal_subtotal_after_discount.cents
    assert_equal 7600, @order.subtotal_after_discount.cents
    assert_equal 9500, OrderLinePricing.new(@order, include_erp_discount: false).export_totals.fetch(@item.id)
  end

  test 'cap restoration never raises an undiscounted ERP line above its base price' do
    @rule.update!(discount_value: 0.9)
    other = @org.products.create!(name: 'Full price', unit_price: 10000, published: true)
    full_price = @order.order_items.create!(product: other, quantity: 1)
    @org.update!(max_discount_percentage: 0.05)
    @order.refresh_cart!
    totals = OrderLinePricing.new(@order, include_erp_discount: false).export_totals
    assert_equal 9000, totals.fetch(@item.id)
    assert_equal 10000, totals.fetch(full_price.id)
    assert_equal 15200, @order.subtotal_after_discount.cents
  end

  test 'tax updates include multiple unsaved nested BO lines with the ERP discount' do
    @order.order_items.build(product: @product, product_variant: @product.default_variant,
      unit_price: 10000, discount_percentage: 0.1, quantity: 1, note: 'new one')
    @order.order_items.build(product: @product, product_variant: @product.default_variant,
      unit_price: 10000, discount_percentage: 0.1, quantity: 1, note: 'new two')
    @order.save!
    assert_equal 21600, @order.reload.subtotal_after_discount.cents
    assert_equal 4968, @order.tax_amount.cents
  end

  test 'manual discounts are included in export without the ERP percentage' do
    @order.update!(discount_type: 'fixed', discount_value: 5)
    assert_equal 8500, @order.nodal_subtotal_after_discount.cents
    assert_equal 6800, @order.subtotal_after_discount.cents
    assert_equal 8500, OrderLinePricing.new(@order, include_erp_discount: false).export_totals.fetch(@item.id)
  end

  test 'zero and full ERP discounts remain valid without dividing prices' do
    @customer.update!(erp_discount_percentage: 100)
    assert_equal 0, @order.subtotal_after_discount.cents
    assert_equal 0, DiscountCalculator.new(product: @product, customer: @customer).final_price.cents
    assert_equal 9000, OrderLinePricing.new(@order, include_erp_discount: false).export_totals.fetch(@item.id)
    @customer.update!(erp_discount_percentage: 0)
    assert_equal 9000, @order.subtotal_after_discount.cents
  end
end
