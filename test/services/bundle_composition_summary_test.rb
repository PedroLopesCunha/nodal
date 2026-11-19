require "test_helper"

class BundleCompositionSummaryTest < ActiveSupport::TestCase
  setup do
    @org = Organisation.create!(name: "Composition summary", currency: "EUR")
    @first = @org.products.create!(name: "Colar", unit_price: 15000, published: true).default_variant
    @second = @org.products.create!(name: "Brincos", unit_price: 7000, published: true).default_variant
    @first.update!(track_stock: true, stock_quantity: 5)
    @second.update!(track_stock: true, stock_quantity: 10)
    @parts = [{ product_variant_id: @first.id, quantity: 2 }, { product_variant_id: @second.id, quantity: 3 }]
  end

  def summary(price = 45000)
    BundleCompositionSummary.new(organisation: @org, components: @parts, price_cents: price).call
  end

  test "sums component quantities and calculates a base price difference" do
    result = summary
    assert_equal 51000, result[:total_cents]
    assert_equal [30000, 21000], result[:lines].map { |line| line[:subtotal_cents] }
    assert_equal 6000, result[:difference_cents]
    assert_equal 11.76, result[:percentage]
    assert_not result[:above_base]
    assert_equal 2, result[:capacity]
  end

  test "uses physical tracked stock even when the sales policy allows backorders" do
    assert @first.sells_without_stock?
    assert_equal 2, summary[:capacity]
    @first.update!(stock_quantity: -1)
    assert_equal 0, summary[:capacity]
  end

  test "untracked components do not invent an available stock quantity" do
    @first.update!(track_stock: false)
    assert_equal 3, summary[:capacity]
    assert_nil summary[:lines].first[:stock_quantity]
    @second.update!(track_stock: false)
    assert_nil summary[:capacity]
  end

  test "handles a missing bundle price and a price above the component total" do
    assert_nil summary(nil)[:difference_cents]
    result = summary(60000)
    assert_equal(-9000, result[:difference_cents])
    assert result[:above_base]
  end

  test "rejects duplicate fractional and foreign variants" do
    @parts << @parts.first
    assert_raises(BundleCompositionSummary::InvalidComposition) { summary }
    @parts.pop
    @parts.first[:quantity] = "1.5"
    assert_raises(BundleCompositionSummary::InvalidComposition) { summary }
    @parts.first[:quantity] = 1
    other = Organisation.create!(name: "Other summary org")
    @parts.first[:product_variant_id] = other.products.create!(name: "Private", unit_price: 100).default_variant.id
    assert_raises(BundleCompositionSummary::InvalidComposition) { summary }
  end

  test "missing component price keeps stock calculation without inventing a zero price" do
    @first.update_column(:unit_price_cents, nil)
    result = summary
    assert_nil result[:total_cents]
    assert_nil result[:difference_cents]
    assert_equal 2, result[:capacity]
    assert result[:warning].present?
  end
end
