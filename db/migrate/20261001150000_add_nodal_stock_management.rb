class AddNodalStockManagement < ActiveRecord::Migration[7.1]
  def change
    add_column :product_variants, :stock_source, :string, default: "erp", null: false
    add_check_constraint :product_variants, "stock_source IN ('erp', 'nodal')", name: "product_variants_stock_source"
    add_column :order_items, :local_stock_consumed, :integer, default: 0, null: false
    add_check_constraint :order_items, "local_stock_consumed >= 0", name: "order_items_local_stock_consumed"
  end
end
