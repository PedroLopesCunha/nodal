require "test_helper"

# Covers the quantity/amount condition engine shared by ProductDiscount and
# CustomerProductDiscount (HasDiscountCondition + DiscountCalculator).
class DiscountConditionTest < ActiveSupport::TestCase
  def setup
    @org = Organisation.create!(name: "Cond Test Org")
    @customer = Customer.create!(organisation: @org, company_name: "Acme", contact_name: "J", active: true)
    @product = Product.create!(organisation: @org, name: "Widget", unit_price: 1000, published: true) # €10
  end

  def final_price(quantity)
    DiscountCalculator.new(product: @product, customer: @customer, quantity: quantity).final_price
  end

  test "product discount with amount condition applies only when the line value meets it" do
    ProductDiscount.create!(organisation: @org, product: @product, discount_type: "percentage",
      discount_value: 0.10, condition_type: "amount", min_amount_cents: 5000) # spend €50 on this line

    assert_equal Money.new(1000, "EUR"), final_price(4) # €40 line < €50 -> no discount
    assert_equal Money.new(900, "EUR"), final_price(5)  # €50 line -> 10% off
  end

  test "product discount with quantity condition still works" do
    ProductDiscount.create!(organisation: @org, product: @product, discount_type: "percentage",
      discount_value: 0.10, condition_type: "quantity", min_quantity: 5)

    assert_equal Money.new(1000, "EUR"), final_price(4)
    assert_equal Money.new(900, "EUR"), final_price(5)
  end

  test "customer special price with no condition always applies" do
    CustomerProductDiscount.create!(organisation: @org, customer: @customer, product: @product,
      discount_type: "percentage", discount_value: 0.20) # condition_type defaults to none

    assert_equal Money.new(800, "EUR"), final_price(1)
  end

  test "customer special price with quantity condition gates on quantity" do
    CustomerProductDiscount.create!(organisation: @org, customer: @customer, product: @product,
      discount_type: "percentage", discount_value: 0.20, condition_type: "quantity", min_quantity: 10)

    assert_equal Money.new(1000, "EUR"), final_price(9)
    assert_equal Money.new(800, "EUR"), final_price(10)
  end

  test "customer special price with amount condition gates on line value" do
    CustomerProductDiscount.create!(organisation: @org, customer: @customer, product: @product,
      discount_type: "fixed", discount_value: 3, condition_type: "amount", min_amount_cents: 10000) # €100 line

    assert_equal Money.new(1000, "EUR"), final_price(9)  # €90 < €100 -> no discount
    assert_equal Money.new(700, "EUR"), final_price(10)  # €100 -> €3 off each unit
  end

  test "amount condition validates a positive minimum" do
    d = ProductDiscount.new(organisation: @org, product: @product, discount_type: "percentage",
      discount_value: 0.10, condition_type: "amount", min_amount_cents: 0)
    assert_not d.valid?
  end

  test "amount-condition product discount ignores the product's min order quantity rule" do
    @product.update!(min_quantity: 50) # high min order qty
    d = ProductDiscount.new(organisation: @org, product: @product, discount_type: "percentage",
      discount_value: 0.10, condition_type: "amount", min_amount_cents: 5000)
    assert d.valid?, d.errors.full_messages.to_sentence # min_quantity rule must not block amount conditions
  end

  test "condition_display summarises the requirement" do
    qty = ProductDiscount.new(condition_type: "quantity", min_quantity: 5)
    amt = ProductDiscount.new(organisation: @org, condition_type: "amount", min_amount_cents: 5000)
    none = CustomerProductDiscount.new(condition_type: "none")
    assert_equal "5", qty.condition_display
    assert_equal "€50.00", amt.condition_display
    assert_equal "—", none.condition_display
  end
end
