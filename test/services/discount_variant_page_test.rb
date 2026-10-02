require 'test_helper'

class DiscountVariantPageTest < ActiveSupport::TestCase
  setup do
    @org = Organisation.create!(name: 'Variant pages')
    @products = 55.times.map do |i|
      @org.products.create!(name: "Product #{i.to_s.rjust(3, '0')}", sku: "PAGE-#{i}", unit_price: 1000)
    end
  end

  test 'pages are bounded and stable without queries per product' do
    queries = []
    subscriber = ->(*args) { payload = args.last; queries << payload[:sql] unless payload[:cached] || payload[:name] == 'SCHEMA' }
    first = nil
    ActiveSupport::Notifications.subscribed(subscriber, 'sql.active_record') do
      first = DiscountVariantPage.new(@org.products)
      first.grouped.each { |product, variants| product.name; variants.each(&:price) }
    end
    assert_equal 50, first.grouped.values.flatten.size
    assert first.next_page?
    assert_operator queries.grep(/SELECT/i).size, :<=, 3
    second = DiscountVariantPage.new(@org.products, page: 2)
    assert_equal 5, second.grouped.values.flatten.size
    assert_not second.next_page?
    assert_empty first.grouped.values.flatten.map(&:id) & second.grouped.values.flatten.map(&:id)
  end

  test 'search respects eligible products and organisation boundaries' do
    foreign = Organisation.create!(name: 'Foreign pages')
    foreign.products.create!(name: 'Product 001', sku: 'PAGE-1', unit_price: 1000)
    result = DiscountVariantPage.new(@org.products, query: 'PAGE-1')
    assert result.grouped.keys.all? { |product| product.organisation_id == @org.id }
    assert_equal [@products.first], DiscountVariantPage.new(@org.products.where(id: @products.first), query: 'Product').grouped.keys
    assert_empty DiscountVariantPage.new(@org.products, query: '%').grouped
  end
end
