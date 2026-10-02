require "test_helper"
require Rails.root.join("db/migrate/20261002100000_create_discount_category_scopes")

class DiscountCategoryScopesMigrationTest < ActiveSupport::TestCase
  test "backfill preserves targets and is repeatable without using domain models" do
    org = Organisation.create!(name: "Migration")
    category = Category.create!(organisation: org, name: "Silver")
    product = Product.create!(organisation: org, name: "Ring", unit_price: 1000)
    category_rule = ProductDiscount.create!(organisation: org, category: category,
      discount_value: 0.08, discount_type: "percentage", condition_scope: "summed", min_quantity: 5)
    product_rule = ProductDiscount.create!(organisation: org, product: product,
      discount_value: 0.08, discount_type: "percentage")
    tier = OrderDiscount.create!(organisation: org, min_order_amount_cents: 75000,
      discount_value: 0.07, discount_type: "percentage")
    migration = CreateDiscountCategoryScopes.new
    ActiveRecord::Migration.suppress_messages { migration.backfill }
    connection = ActiveRecord::Base.connection
    assert_equal %w[include include], connection.select_values("SELECT mode FROM discount_category_scopes WHERE product_discount_id = #{category_rule.id} ORDER BY role")
    assert_equal %w[all all], connection.select_values("SELECT mode FROM discount_category_scopes WHERE product_discount_id = #{product_rule.id} ORDER BY role")
    assert_equal 2, connection.select_value("SELECT COUNT(*) FROM discount_category_scope_categories sc JOIN discount_category_scopes s ON s.id = sc.discount_category_scope_id WHERE s.product_discount_id = #{category_rule.id}").to_i
    assert tier.reload.order_discount_campaign_id
    counts = %w[discount_category_scopes discount_category_scope_categories order_discount_campaigns].map { |table| connection.select_value("SELECT COUNT(*) FROM #{table}") }
    ActiveRecord::Migration.suppress_messages { migration.backfill }
    assert_equal counts, %w[discount_category_scopes discount_category_scope_categories order_discount_campaigns].map { |table| connection.select_value("SELECT COUNT(*) FROM #{table}") }
    assert_equal "summed", category_rule.reload.condition_scope
    assert_equal 5, category_rule.min_quantity
  end
end
