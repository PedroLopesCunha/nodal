class AddErpDiscountToCustomersAndOrders < ActiveRecord::Migration[7.1]
  def change
    # ERP percentages use human units: 20 means 20%, not 0.20.
    add_column :customers, :erp_discount_percentage, :decimal, precision: 7, scale: 4, default: 0, null: false
    # Zero preserves historical orders; drafts read the current customer value.
    add_column :orders, :erp_discount_percentage, :decimal, precision: 7, scale: 4, default: 0, null: false
    add_check_constraint :customers, 'erp_discount_percentage BETWEEN 0 AND 100', name: 'customers_erp_discount_range'
    add_check_constraint :orders, 'erp_discount_percentage BETWEEN 0 AND 100', name: 'orders_erp_discount_range'
  end
end
