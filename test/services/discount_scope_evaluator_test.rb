require "test_helper"

class DiscountScopeEvaluatorTest < ActiveSupport::TestCase
  def setup
    @org = Organisation.create!(name: "Scopes")
    @parent = Category.create!(organisation: @org, name: "Molduras")
    @child = Category.create!(organisation: @org, name: "Small", parent: @parent)
    @other = Category.create!(organisation: @org, name: "Silver")
    @product = Product.create!(organisation: @org, name: "Frame", unit_price: 10000)
    @product.categories = [@child, @other]
    @uncategorized = Product.create!(organisation: @org, name: "Loose", unit_price: 20000)
    @items = [@product, @uncategorized].map do |product|
      OrderItem.new(product: product, product_variant: product.default_variant, quantity: 1,
        unit_price: product.unit_price, discount_percentage: 0.1)
    end
    @campaign = OrderDiscountCampaign.create!(organisation: @org, name: "October", priority: 1)
    @evaluator = DiscountScopeEvaluator.new(@items)
  end

  test "include counts a line once across overlapping categories and ancestors" do
    @campaign.configure_category_scopes(mode: "include", category_ids: [@parent.id, @child.id, @other.id])
    assert_equal 10000, @evaluator.amount_cents_for(scope: @campaign.qualification_scope)
    assert_equal 1, @evaluator.quantity_for(scope: @campaign.qualification_scope)
  end

  test "exclude wins for a product also in an included category and includes uncategorized products" do
    @campaign.configure_category_scopes(mode: "exclude", category_ids: [@parent.id])
    assert_equal [@items.last], @evaluator.items_for(scope: @campaign.discount_scope)
  end

  test "all includes uncategorized products and preserves separate monetary bases" do
    assert_equal 30000, @evaluator.amount_cents_for(scope: @campaign.qualification_scope)
    assert_equal 27000, @evaluator.amount_cents_for(scope: @campaign.qualification_scope, basis: :after_line_discounts)
  end

  test "qualification and discount scopes can differ in the domain" do
    @campaign.qualification_scope.mode = "include"
    @campaign.qualification_scope.categories = [@parent]
    assert_equal 10000, @evaluator.amount_cents_for(scope: @campaign.qualification_scope)
    assert_equal 30000, @evaluator.amount_cents_for(scope: @campaign.discount_scope)
  end

  test "variant exclusion is an explicit policy rather than part of category matching" do
    @items.first.product_variant.exclude_from_discounts = true
    assert_equal 30000, @evaluator.amount_cents_for(scope: @campaign.discount_scope)
    assert_equal 20000, @evaluator.amount_cents_for(scope: @campaign.discount_scope, exclude_variants: true)
  end

  test "categories and owners must belong to the same organisation" do
    foreign = Organisation.create!(name: "Foreign")
    category = Category.create!(organisation: foreign, name: "Foreign")
    assert_raises(ActiveRecord::RecordNotFound) { @campaign.configure_category_scopes(mode: "include", category_ids: [category.id]) }
    scope = @campaign.qualification_scope
    scope.categories = [@parent]
    scope.mode = "include"
    scope.organisation = foreign
    assert_not scope.valid?
    assert_not scope.matches_product?(@product)
  end

  test "referenced categories cannot be silently destroyed" do
    @campaign.configure_category_scopes(mode: "exclude", category_ids: [@other.id])
    @campaign.save!
    assert_not @other.destroy
    assert Category.exists?(@other.id)
  end
  test "discarding a descendant cannot silently remove an exclusion" do
    @campaign.configure_category_scopes(mode: "exclude", category_ids: [@parent.id])
    @campaign.save!
    assert_not @child.discard
    assert_not @child.discarded?
    assert @product.reload.categories.include?(@child)
  end

  test "organisation deletion cleans scopes before removing referenced categories" do
    @campaign.configure_category_scopes(mode: "exclude", category_ids: [@other.id])
    @campaign.save!
    assert @org.destroy
    assert_not DiscountCategoryScope.exists?(organisation_id: @org.id)
  end

  test "scope category changes stay in memory until the owner is saved" do
    @campaign.configure_category_scopes(mode: "include", category_ids: [@parent.id])
    assert_equal 0, DiscountCategoryScopeCategory.where(discount_category_scope_id: @campaign.category_scopes.map(&:id)).count
    @campaign.save!
    assert_equal [@parent.id], @campaign.reload.discount_scope.selected_category_ids
    @campaign.configure_category_scopes(mode: "include", category_ids: [@other.id])
    assert_equal [@parent.id], DiscountCategoryScope.find(@campaign.discount_scope.id).selected_category_ids
    @campaign.save!
    assert_equal [@other.id], @campaign.reload.discount_scope.selected_category_ids
  end

end
