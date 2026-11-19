require "test_helper"
require "minitest/mock"

class BundleCartServiceTest < ActiveSupport::TestCase
  setup do
    @org = Organisation.create!(name: "Bundle Org", currency: "EUR", out_of_stock_strategy: "hide")
    @customer = @org.customers.create!(company_name: "Buyer", contact_name: "Buyer", active: true, external_id: "C1")
    @user = @customer.customer_users.create!(organisation: @org, email: "bundle-buyer@example.com", password: "password123", active: true)
    @order = @org.orders.create!(customer: @customer, customer_user: @user)
    @first = @org.products.create!(name: "Necklace", published: true, unit_price: 15000, sku: "ABC")
    @second = @org.products.create!(name: "Earrings", published: true, unit_price: 7000, sku: "XYZ")
    @third = @org.products.create!(name: "Ring", published: true, unit_price: 5000, sku: "123")
    [@first, @second, @third].each do |product|
      product.default_variant.update!(stock_quantity: 10, track_stock: true, published: true)
      StockRulesService.new(@org).apply_to_variant(product.default_variant)
    end
    @bundle = @org.products.create!(name: "Aurora", bundle: true, published: true, unit_price: 25000,
      bundle_components_attributes: [@first, @second, @third].map { |p| { product_variant_id: p.default_variant.id, quantity: 1 } })
    @service = BundleCartService.new(@order)
  end

  test "confirmation email and PDF group saved bundles and retain ordinary purchases" do
    @customer.update!(erp_discount_percentage: 20)
    group = @service.add!(@bundle, 2)
    @order.order_items.create!(product: @third, product_variant: @third.default_variant, quantity: 1)
    @order.place!
    @bundle.update!(name: "Renamed live set")
    @first.update!(name: "Renamed live component")
    EmailDeliveryGuard.stub(:should_send?, true) do
      mail = CustomerMailer.with(customer_user: @user, order: @order).confirm_order
      html = Nokogiri::HTML(mail.html_part.body.decoded)
      rows = html.css("tr[data-order-bundle]")
      assert_equal 1, rows.length
      assert_includes rows.first.text, "Aurora"
      assert_includes rows.first.text, "Necklace"
      assert_includes rows.first.text, "XYZ"
      assert_not_includes rows.first.text, "Renamed live"
      assert_includes rows.first.text, group.customer_total.format
      assert_includes mail.text_part.body.decoded, "Aurora x2"
      assert_includes mail.text_part.body.decoded, "Ring x1"
    end
    html = ApplicationController.render(template: "shared/orders/pdf", layout: false, assigns: { order: @order, organisation: @org })
    doc = Nokogiri::HTML(html)
    assert_equal 1, doc.css("tr[data-order-bundle]").length
    assert_equal 2, doc.css("tbody tr").length
    assert_includes doc.css("tr[data-order-bundle]").text, "Necklace"
  end

  test "bundle components bypass individual minimums at checkout but ordinary lines do not" do
    @first.update!(min_quantity: 5)
    @service.add!(@bundle.reload, 1)
    @order.validate_minimum_quantities!
    ordinary = @order.order_items.build(product: @first, product_variant: @first.default_variant, quantity: 5)
    ordinary.save!
    ordinary.update_column(:quantity, 1)
    assert_raises(ActiveRecord::RecordInvalid) { @order.validate_minimum_quantities! }
  end

  test "combined minimum ignores bundled lines and still checks ordinary purchases" do
    @first.update!(has_variants: true, min_quantity: 5, min_quantity_scope: "combined")
    variant = @first.product_variants.create!(name: "Red", sku: "ABC-R", unit_price_cents: 15000,
      published: true, is_default: false, track_stock: true, stock_quantity: 10)
    @bundle.bundle_components.find_by!(product_variant_id: @first.default_variant.id).update!(product_variant: variant)
    @service.add!(@bundle.reload, 1)
    assert_empty @order.combined_min_quantity_shortfalls
    @order.validate_minimum_quantities!
    @order.order_items.create!(product: @first, product_variant: variant, quantity: 4, unit_price: 15000)
    shortfall = @order.combined_min_quantity_shortfalls.sole
    assert_equal 4, shortfall[:current]
    assert_equal 1, shortfall[:shortfall]
    assert_raises(ActiveRecord::RecordInvalid) { @order.validate_minimum_quantities! }
  end

  test "bundle is made of actual components with an exact exclusive price" do
    @org.product_discounts.create!(product: @first, discount_type: "percentage", discount_value: 0.5)
    group = @service.add!(@bundle, 1)
    assert_equal 3, group.order_items.count
    assert_equal [13889, 6481, 4630], group.order_items.order(:id).pluck(:bundle_amount_cents)
    assert_equal 25000, @order.reload.total_amount.cents
    assert_equal 25000, OrderLinePricing.new(@order).export_totals.values.sum
    @order.refresh_cart!
    assert_equal 25000, @order.reload.total_amount.cents
    assert group.order_items.all? { |item| item.discount_percentage.zero? }
  end

  test "individual purchases and multiple bundles share stock without merging lines" do
    @order.order_items.create!(product: @first, quantity: 1)
    a = @service.add!(@bundle, 2)
    b = @service.add!(@bundle, 1)
    assert_equal 7, @order.order_items.count
    assert_equal 90000, @order.reload.total_amount.cents
    @service.update!(a, 3)
    assert_equal 3, a.reload.quantity
    assert_equal [3, 3, 3], a.order_items.pluck(:quantity)
    assert_raises(ArgumentError) { @service.update!(b, 7) }
    assert_equal 1, b.reload.quantity
    assert_equal [1, 1, 1], b.order_items.pluck(:quantity)
    assert_raises(ArgumentError) { @service.add!(@bundle, 10) }
    assert_equal 2, @order.order_bundles.count
  end

  test "component quantities constrain bundle stock" do
    @bundle.bundle_components.find_by(product_variant: @second.default_variant).update!(quantity: 2)
    @bundle.reload.refresh_bundle_inventory!
    assert_equal 5, @bundle.reload.bundle_capacity
    @second.default_variant.update!(stock_quantity: 0)
    assert_not @bundle.reload.available?
    assert_not @bundle.bundle_purchasable?
  end

  test "campaigns manual discounts coupons and cap do not reduce bundle prices" do
    @org.order_discounts.create!(min_order_amount_cents: 1, discount_type: "percentage", discount_value: 0.5)
    @service.add!(@bundle, 1)
    assert_nil @order.automatic_discount_evaluation
    @order.update!(discount_type: "fixed", discount_value: 1000)
    assert_equal 25000, @order.nodal_subtotal_after_discount.cents
    @order.order_items.create!(product: @first, quantity: 1)
    assert_equal 25000, @order.nodal_subtotal_after_discount.cents
    totals = OrderLinePricing.new(@order).export_totals
    assert_equal 25000, totals.values.sum
    @org.update!(max_discount_percentage: 0.1)
    @order.reload
    assert_equal 38500, @order.nodal_subtotal_after_discount.cents
  end

  test "commercial ERP discount remains separate from export" do
    @customer.update!(erp_discount_percentage: 20)
    @service.add!(@bundle, 1)
    assert_equal 25000, OrderLinePricing.new(@order).export_totals.values.sum
    assert_equal 20000, @order.subtotal_after_discount.cents
  end

  test "checkout refuses combined stock overflow even if ordinary checkout permits backorders" do
    @org.update!(checkout_stock_policy: "allow", cart_stock_policy: "warn", cart_qty_overflow_policy: "warn")
    @service.add!(@bundle, 5)
    @order.order_items.create!(product: @first, quantity: 6)
    assert_raises(ActiveRecord::RecordInvalid) { @order.validate_checkout_stock! }
  end

  test "composition name and price remain snapshots after product edits" do
    group = @service.add!(@bundle, 1)
    @order.place!
    @bundle.update!(name: "New name", unit_price: 18000)
    @first.update!(name: "New necklace", unit_price: 30000)
    assert_equal "Aurora", group.reload.name
    assert_equal "Necklace", group.composition.first["name"]
    assert_equal 25000, group.total_price.cents
    assert_equal 25000, @order.reload.total_amount.cents
  end

  test "draft bundle prices refresh but a changed composition must be added again" do
    group = @service.add!(@bundle, 1)
    @bundle.update!(unit_price: 24000)
    changes = @order.refresh_cart!
    assert_equal 3, changes[:price_changed].size
    assert_equal 24000, @order.reload.total_amount.cents
    assert_equal 24000, group.reload.total_price.cents
    @bundle.bundle_components.first.update!(quantity: 2)
    assert_not group.reload.current_composition?
    assert_equal 0, group.capacity_in_cart
    assert_raises(ActiveRecord::RecordInvalid) { @order.validate_checkout_stock! }
  end

  test "cart caps whole bundles rather than modifying individual components" do
    @org.update!(cart_qty_overflow_policy: "cap", cart_stock_policy: "warn")
    group = @service.add!(@bundle, 5)
    @first.default_variant.update!(stock_quantity: 3)
    @order.refresh_cart!
    assert_equal 3, group.reload.quantity
    assert_equal [3, 3, 3], group.order_items.pluck(:quantity)
    assert_equal 75000, @order.reload.total_amount.cents
  end

  test "rejects another organisation components nested bundles and fractional quantities" do
    other = Organisation.create!(name: "Other")
    external = other.products.create!(name: "Outside", unit_price: 100)
    component = @bundle.bundle_components.build(product_variant: external.default_variant, quantity: 1)
    assert_not component.valid?
    assert_not @bundle.bundle_components.build(product_variant: @bundle.default_variant, quantity: 1).valid?
    assert_raises(ArgumentError) { @service.add!(@bundle, "1.5") }
    assert_raises(ArgumentError) { @service.add!(@bundle, "-1") }
  end

  test "existing export receives only components with prices totalling the bundle" do
    @org.create_erp_configuration!(enabled: true, adapter_type: "custom_api", sync_orders: true, product_sync_mode: "update_only",
      credentials: { base_url: "https://example.test", api_key: "test" })
    @service.add!(@bundle, 1)
    @order.place!
    service = Erp::OrderPushService.new(order: @order)
    data = service.send(:serialize_order)
    assert_equal ["ABC", "XYZ", "123"], data[:items].map { |i| i[:product_code] }
    assert_equal 25000, data[:items].sum { |i| (i[:unit_price] * i[:quantity] * 100).round }
  end

  test "local stock is consumed and restored for actual components only" do
    [@first, @second, @third].each { |p| p.default_variant.update!(stock_source: "nodal") }
    @service.add!(@bundle, 2)
    @order.place!
    assert_equal [8, 8, 8], [@first, @second, @third].map { |p| p.default_variant.reload.stock_quantity }
    assert_equal 8, @bundle.reload.bundle_capacity
    @order.destroy!
    assert_equal [10, 10, 10], [@first, @second, @third].map { |p| p.default_variant.reload.stock_quantity }
  end

  test "multiple component quantities keep totals exact including a one cent bundle" do
    @bundle.bundle_components.first.update!(quantity: 3)
    @bundle.update!(unit_price: 1)
    group = @service.add!(@bundle.reload, 2)
    assert_equal 2, group.total_price.cents
    assert_equal 2, @order.reload.total_amount.cents
    assert_equal 2, OrderLinePricing.new(@order).export_totals.values.sum
  end

  test "coupon only discounts normal purchases" do
    @service.add!(@bundle, 1)
    coupon = @org.promo_codes.create!(code: "BUNDLETEST", discount_type: "percentage", discount_value: 0.5, eligibility: "all_customers")
    @order.update!(promo_code: coupon)
    assert_equal 25000, @order.nodal_subtotal_after_discount.cents
    @order.order_items.create!(product: @first, quantity: 1)
    assert_equal 32500, @order.nodal_subtotal_after_discount.cents
    assert_equal 32500, OrderLinePricing.new(@order).export_totals.values.sum
  end
end
