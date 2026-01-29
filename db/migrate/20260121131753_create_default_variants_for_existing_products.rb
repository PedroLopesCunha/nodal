class CreateDefaultVariantsForExistingProducts < ActiveRecord::Migration[7.1]
  def up
    # Create a default variant for each existing product
    execute <<-SQL
      INSERT INTO product_variants (organisation_id, product_id, name, sku, unit_price_cents, unit_price_currency, available, is_default, position, created_at, updated_at)
      SELECT
        p.organisation_id,
        p.id,
        p.name,
        p.sku,
        p.unit_price,
        COALESCE(o.currency, 'EUR'),
        p.available,
        true,
        1,
        NOW(),
        NOW()
      FROM products p
      JOIN organisations o ON o.id = p.organisation_id
      WHERE NOT EXISTS (
        SELECT 1 FROM product_variants pv WHERE pv.product_id = p.id
      )
    SQL
  end

  def down
    # Remove all default variants created by this migration
    execute <<-SQL
      DELETE FROM product_variants WHERE is_default = true
    SQL
  end
end
