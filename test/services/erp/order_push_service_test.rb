require "test_helper"
require "minitest/mock"

module Erp
  # A real order failed to reach the ERP because of a SKU that did not exist
  # there. Once the line was corrected, "retry" left the order at `pending`
  # forever: the attempt budget was spent, the service refused without saying
  # so, and the retry button only shows for `failed` — so it disappeared at the
  # moment it was needed.
  class OrderPushServiceTest < ActiveSupport::TestCase
    # Stands in for the Firebird adapter, which cannot be reached from a test
    # (or from a development machine).
    class FakeAdapter
      attr_reader :pushed

      def initialize(response = { success: true, external_id: "ERP-1" })
        @response = response
        @pushed = []
      end

      def supports_push? = true

      def push_order(payload)
        @pushed << payload
        @response
      end
    end

    setup do
      @organisation = Organisation.create!(name: "Push Org", currency: "EUR")
      @erp_config = ErpConfiguration.create!(
        organisation: @organisation, enabled: true, adapter_type: "custom_api",
        credentials: { base_url: "https://erp.exemplo.pt", api_key: "k" },
        sync_frequency: "daily", product_sync_mode: "update_only", sync_orders: true
      )
      @customer = @organisation.customers.create!(company_name: "Cliente", contact_name: "Rui",
                                                  active: true, external_id: "C-1")
      @login = @customer.customer_users.create!(organisation: @organisation, contact_name: "Rui",
                                                email: "rui-push@exemplo.pt", password: "password123")
      @order = @organisation.orders.create!(customer: @customer, customer_user: @login,
                                            status: "in_process", placed_at: Time.current)
    end

    # The service loads its own copy of the configuration, so the adapter is
    # stubbed on that one — there is no Firebird to talk to from a test.
    def push(adapter = FakeAdapter.new)
      service = OrderPushService.new(order: @order)
      config = service.instance_variable_get(:@erp_config)

      config.stub(:adapter, adapter) { service.call }
    end

    test "a successful push marks the order synced" do
      result = push

      assert result.success?
      assert_equal "synced", @order.reload.push_status
    end

    # The bug, in one test: an order that has spent its attempts must not be
    # left looking like it is still on its way.
    test "an order out of attempts is recorded as failed, not left pending" do
      @order.update!(push_attempts: Order::MAX_PUSH_ATTEMPTS, push_status: "pending")

      result = push

      assert_not result.success?
      assert_equal "failed", @order.reload.push_status
      assert_match(/attempts exhausted/i, @order.sync_error)
    end

    test "an order whose customer is unknown to the ERP says so" do
      @customer.update!(external_id: nil)

      result = push

      assert_not result.success?
      assert_equal "failed", @order.reload.push_status
      assert_match(/external_id/, @order.sync_error)
    end

    # These say nothing about the order itself, so they must not brand it.
    test "an already synced order is left untouched" do
      @order.update!(push_status: "synced", push_attempts: 1)

      push

      assert_equal "synced", @order.reload.push_status
      assert_nil @order.sync_error
    end

    test "a draft order is not branded as failed" do
      @order.update!(placed_at: nil, push_status: "pending")

      push

      assert_equal "pending", @order.reload.push_status
      assert_nil @order.sync_error
    end

    def place_campaign_order(line_stackable: false, campaign_stackable: false, quantity: 11,
      campaign_type: 'percentage', campaign_value: 0.12)
      @order.update!(placed_at: nil)
      @product = @organisation.products.create!(name: 'Silver', sku: 'ERP-SILVER', unit_price: 10000, published: true)
      @rule = @organisation.product_discounts.create!(product: @product, discount_type: 'percentage',
        discount_value: 0.05, stackable: line_stackable)
      @campaign = @organisation.order_discount_campaigns.create!(name: 'October', priority: 1)
      @tier = @organisation.order_discounts.create!(order_discount_campaign: @campaign,
        min_order_amount_cents: 100000, discount_type: campaign_type, discount_value: campaign_value,
        stackable: campaign_stackable)
      @order.order_items.create!(product: @product, quantity: quantity)
      yield if block_given?
      @order.terms_accepted_at = Time.current
      @order.finalize_checkout!
    end

    test 'ERP receives the campaign price replacing the category price' do
      place_campaign_order
      adapter = FakeAdapter.new
      assert push(adapter).success?
      assert_equal [{ product_code: 'ERP-SILVER', quantity: 11, unit_price: 88.0 }], adapter.pushed.first[:items]
    end

    test 'ERP receives compounded prices only when both rules allow stacking' do
      place_campaign_order(line_stackable: true, campaign_stackable: true)
      adapter = FakeAdapter.new
      assert push(adapter).success?
      assert_equal 83.6, adapter.pushed.first[:items].first[:unit_price]
    end

    test 'fixed allocations use subcent unit prices rather than rounding each unit to cents' do
      place_campaign_order(quantity: 100, line_stackable: true, campaign_stackable: true,
        campaign_type: 'fixed', campaign_value: 0.01)
      adapter = FakeAdapter.new
      assert push(adapter).success?
      assert_equal 94.9999, adapter.pushed.first[:items].first[:unit_price]
    end

    test 'excluded lines retain their category price in the payload' do
      place_campaign_order do
        frames = @organisation.categories.create!(name: 'Molduras')
        @campaign.configure_category_scopes(mode: 'exclude', category_ids: [frames.id])
        @campaign.save!
        product = @organisation.products.create!(name: 'Frame', sku: 'ERP-FRAME', unit_price: 20000, published: true)
        product.categories = [frames]
        @organisation.product_discounts.create!(product: product, discount_type: 'percentage', discount_value: 0.05)
        @order.order_items.create!(product: product, quantity: 1)
      end
      adapter = FakeAdapter.new
      assert push(adapter).success?
      assert_equal [88.0, 190.0], adapter.pushed.first[:items].map { |item| item[:unit_price] }
    end

    test 'unrepresentable totals fail before sending an incorrect rounded amount' do
      place_campaign_order(quantity: 1000, line_stackable: true, campaign_stackable: true,
        campaign_type: 'fixed', campaign_value: 0.01)
      adapter = FakeAdapter.new
      result = push(adapter)
      assert_not result.success?
      assert_empty adapter.pushed
      assert_match(/4 decimal places/, result.error)
    end

    test 'later rule edits do not change the prices pushed to ERP' do
      place_campaign_order
      @rule.update!(discount_value: 0.50, stackable: true)
      @tier.update!(discount_value: 0.90, stackable: true)
      adapter = FakeAdapter.new
      assert push(adapter).success?
      assert_equal 88.0, adapter.pushed.first[:items].first[:unit_price]
    end

    test 'half cent boundaries are refused rather than depending on ERP rounding mode' do
      place_campaign_order(quantity: 250, line_stackable: true, campaign_stackable: true,
        campaign_type: 'fixed', campaign_value: 0.07)
      adapter = FakeAdapter.new
      assert_not push(adapter).success?
      assert_empty adapter.pushed
    end

    test 'stronger line prices survive an exclusive campaign in the ERP payload' do
      place_campaign_order(quantity: 20) { @rule.update!(discount_value: 0.20) }
      adapter = FakeAdapter.new
      assert push(adapter).success?
      assert_equal 80.0, adapter.pushed.first[:items].first[:unit_price]
    end

    test 'inconsistent saved allocations are refused before the adapter is called' do
      place_campaign_order
      @order.update!(auto_discount_amount_cents: @order.auto_discount_amount_cents + 1)
      adapter = FakeAdapter.new
      result = push(adapter)
      assert_not result.success?
      assert_empty adapter.pushed
      assert_match(/inconsistent recorded line allocations/, result.error)
    end

    test 'legacy campaign amounts without line allocations are refused without sending wrong prices' do
      product = @organisation.products.create!(name: 'Legacy', sku: 'OLD', unit_price: 10000)
      @order.order_items.create!(product: product, quantity: 1)
      @order.update!(auto_discount_amount_cents: 1200, auto_discount_type: 'percentage', auto_discount_value: 0.12)
      adapter = FakeAdapter.new
      result = push(adapter)
      assert_not result.success?
      assert_empty adapter.pushed
      assert_match(/line allocations/i, result.error)
      assert @order.reload.push_failed?
    end

    test 'legacy orders without campaigns retain their recorded line prices' do
      product = @organisation.products.create!(name: 'Legacy', sku: 'OLD', unit_price: 10000)
      item = @order.order_items.create!(product: product, quantity: 3)
      item.update_column(:discount_percentage, 0.05)
      adapter = FakeAdapter.new
      assert push(adapter).success?
      assert_equal 95.0, adapter.pushed.first[:items].first[:unit_price]
    end

    test 'an old linked tier without a recorded amount is not evaluated using current rules' do
      tier = @organisation.order_discounts.create!(min_order_amount_cents: 10000,
        discount_type: 'percentage', discount_value: 0.12)
      @order.update!(order_discount: tier)
      adapter = FakeAdapter.new
      result = push(adapter)
      assert_not result.success?
      assert_empty adapter.pushed
      assert_match(/no recorded amount/, result.error)
    end
  end
end
