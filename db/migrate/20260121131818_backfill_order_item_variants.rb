class BackfillOrderItemVariants < ActiveRecord::Migration[7.1]
  def up
    # Link existing order_items to their product's default variant
    execute <<-SQL
      UPDATE order_items
      SET product_variant_id = (
        SELECT pv.id
        FROM product_variants pv
        WHERE pv.product_id = order_items.product_id
        AND pv.is_default = true
        LIMIT 1
      )
      WHERE product_variant_id IS NULL
    SQL
  end

  def down
    # Remove variant associations from order_items
    execute <<-SQL
      UPDATE order_items SET product_variant_id = NULL
    SQL
  end
end
