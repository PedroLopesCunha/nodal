class ScopeOrderItemUniquenessForBundles < ActiveRecord::Migration[7.1]
  def up
    remove_index :order_items, name: "idx_order_items_order_product_variant_note"
    add_index :order_items, "order_id, product_id, product_variant_id, COALESCE(note, '')",
      name: "idx_order_items_order_product_variant_note", unique: true, where: "order_bundle_id IS NULL"
    add_index :order_items, [:order_bundle_id, :product_variant_id], unique: true,
      where: "order_bundle_id IS NOT NULL", name: "idx_order_bundle_variant"
    add_check_constraint :order_items,
      "order_bundle_id IS NULL OR (bundle_amount_cents >= 0 AND bundle_component_quantity > 0 AND bundle_amount_cents IS NOT NULL AND bundle_component_quantity IS NOT NULL)",
      name: "order_bundle_line_amounts"
  end

  def down
    remove_check_constraint :order_items, name: "order_bundle_line_amounts"
    remove_index :order_items, name: "idx_order_bundle_variant"
    remove_index :order_items, name: "idx_order_items_order_product_variant_note"
    add_index :order_items, "order_id, product_id, product_variant_id, COALESCE(note, '')",
      name: "idx_order_items_order_product_variant_note", unique: true
  end
end
