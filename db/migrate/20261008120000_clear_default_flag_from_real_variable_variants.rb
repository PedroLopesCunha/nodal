class ClearDefaultFlagFromRealVariableVariants < ActiveRecord::Migration[7.1]
  def up
    # Only clear an attribute-bearing default when a separate internal base
    # exists. Legacy bases may have attributes themselves; preserve those.
    execute <<~SQL
      UPDATE product_variants
      SET is_default = FALSE
      WHERE is_default = TRUE
        AND EXISTS (
          SELECT 1 FROM products
          WHERE products.id = product_variants.product_id
            AND products.has_variants = TRUE
        )
        AND EXISTS (
          SELECT 1 FROM variant_attribute_values
          WHERE variant_attribute_values.product_variant_id = product_variants.id
        )
        AND EXISTS (
          SELECT 1 FROM product_variants base
          WHERE base.product_id = product_variants.product_id
            AND base.id <> product_variants.id
            AND base.is_default = TRUE
            AND NOT EXISTS (
              SELECT 1 FROM variant_attribute_values base_values
              WHERE base_values.product_variant_id = base.id
            )
        )
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Incorrect default flags cannot be reconstructed"
  end
end
