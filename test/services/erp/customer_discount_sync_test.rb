require 'test_helper'

class CustomerDiscountSyncTest < ActiveSupport::TestCase
  setup do
    @org = Organisation.create!(name: 'ERP discount sync')
    @customer = @org.customers.create!(company_name: 'Buyer', contact_name: 'Ana', active: true,
      erp_discount_percentage: 20)
    @sync = Erp::Sync::CustomerSyncService.allocate
    @attrs = { company_name: 'Buyer', contact_name: 'Ana', active: true }
  end

  test 'synchronizes changed ERP percentages and explicit zero without touching internal discounts' do
    internal = @customer.customer_discounts.create!(organisation: @org, discount_type: 'percentage', discount_value: 0.1)
    [BigDecimal('12.5'), BigDecimal('0')].each do |value|
      @sync.send(:update_customer_attributes, @customer, @attrs.merge(erp_discount_percentage: value), false)
      @customer.save!
      assert_equal value, @customer.reload.erp_discount_percentage
    end
    assert_equal BigDecimal('0.1'), internal.reload.discount_value
  end

  test 'an integration without a mapped discount preserves the existing condition' do
    @sync.send(:update_customer_attributes, @customer, @attrs, false)
    assert_equal 20, @customer.erp_discount_percentage
  end

  test 'both adapters read human percentages only when explicitly mapped' do
    [Erp::Adapters::FirebirdAdapter, Erp::Adapters::CustomApiAdapter].each do |klass|
      adapter = klass.new(field_mappings: { customers: { erp_discount_percentage: 'DESCONTO' } })
      ['20', '12,5', 0, 100, nil, ''].zip([20, 12.5, 0, 100, 0, 0]).each do |raw, expected|
        assert_equal expected, adapter.send(:normalize_customer, { 'DESCONTO' => raw })[:erp_discount_percentage]
      end
      unmapped = klass.new({})
      assert_not unmapped.send(:normalize_customer, { 'discount' => 20 }).key?(:erp_discount_percentage)
    end
  end

  test 'malformed out-of-range and overprecision ERP conditions are rejected' do
    adapter = Erp::Adapters::CustomApiAdapter.new(field_mappings: { customers: { erp_discount_percentage: 'discount' } })
    ['oops', '-1', '101', 'NaN', 'Infinity', '12.12345'].each do |raw|
      assert_raises(ArgumentError) { adapter.send(:normalize_customer, { 'discount' => raw }) }
    end
  end

  test 'customer validation rejects invalid ERP rates' do
    [-1, 101].each do |value|
      @customer.erp_discount_percentage = value
      assert_not @customer.valid?
      assert @customer.errors[:erp_discount_percentage].any?
    end
  end
end
