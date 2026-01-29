class AddVariantToOrderItems < ActiveRecord::Migration[7.1]
  def change
    add_reference :order_items, :product_variant, null: true, foreign_key: true

    # Update composite index to include variant
    remove_index :order_items, [:order_id, :product_id], if_exists: true
    add_index :order_items, [:order_id, :product_id, :product_variant_id], unique: true, name: 'idx_order_items_order_product_variant'
  end
end
