class AllowCartLinesWithDistinctNotes < ActiveRecord::Migration[7.1]
  def up
    remove_index :order_items, name: "idx_order_items_order_product_variant"
    add_index :order_items, "order_id, product_id, product_variant_id, COALESCE(note, '')",
              unique: true, name: "idx_order_items_order_product_variant_note"
  end

  def down
    # Separate configurations cannot be merged without losing their notes.
    raise ActiveRecord::IrreversibleMigration, "Cart lines may have distinct notes for the same variant"
  end
end
