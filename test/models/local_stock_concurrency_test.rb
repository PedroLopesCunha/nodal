require "test_helper"
require "timeout"

# Separate real connections are necessary: transactional fixtures would make
# both threads share a connection and would not exercise PostgreSQL row locks.
class LocalStockConcurrencyTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  setup do
    @org = Organisation.create!(name: "Concurrent Stock #{SecureRandom.hex(4)}", checkout_stock_policy: "block",
      cart_stock_policy: "warn", cart_qty_overflow_policy: "warn", out_of_stock_strategy: "deactivate")
    @customer = @org.customers.create!(company_name: "Buyer", contact_name: "Ana", active: true)
    @user = @customer.customer_users.create!(organisation: @org, email: "concurrent-#{SecureRandom.hex(4)}@example.test",
      password: "password123", password_confirmation: "password123", contact_name: "Ana", active: true)
    @product = @org.products.create!(name: "Last unit", unit_price: 1000, published: true)
    @variant = @product.default_variant
    @variant.update!(stock_source: "nodal", stock_quantity: 1)
    @orders = 2.times.map do
      order = Order.create!(organisation: @org, customer: @customer, customer_user: @user, terms_accepted_at: Time.current)
      order.order_items.create!(product: @product, quantity: 1)
      order
    end
  end

  teardown do
    @orders&.each { |order| order.reload.destroy! }
    @product&.destroy!
    @user&.destroy!
    @customer&.destroy!
    @org&.destroy!
  end

  test "simultaneous checkouts can only sell the last unit once" do
    ready = Queue.new
    start = Queue.new
    workers = @orders.map do |order|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          cart = Order.find(order.id)
          cart.order_items.includes(:product_variant).load
          ready << true
          start.pop
          begin
            cart.finalize_checkout!
            :placed
          rescue ActiveRecord::RecordInvalid
            :rejected
          end
        end
      end
    end
    results = Timeout.timeout(15) do
      2.times { ready.pop }
      2.times { start << true }
      workers.map(&:value)
    end
    assert_equal [:placed, :rejected], results.sort
    assert_equal 0, @variant.reload.stock_quantity
    assert_equal 1, @org.orders.placed.count
    assert_equal 1, OrderItem.where(order_id: @orders.map(&:id)).sum(:local_stock_consumed)
  ensure
    workers&.each { |worker| worker.kill if worker.alive? }
    workers&.each(&:join)
  end
end
