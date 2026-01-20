class MigrateProductCategoriesData < ActiveRecord::Migration[7.1]
  def up
    # Generate slugs for existing categories
    execute <<-SQL
      UPDATE categories
      SET slug = LOWER(REPLACE(name, ' ', '-'))
      WHERE slug IS NULL
    SQL

    # Copy existing product-category relationships to the join table
    execute <<-SQL
      INSERT INTO category_products (category_id, product_id, position, created_at, updated_at)
      SELECT category_id, id, 0, NOW(), NOW()
      FROM products
      WHERE category_id IS NOT NULL
    SQL
  end

  def down
    # Clear the join table
    execute "DELETE FROM category_products"

    # Clear slugs
    execute "UPDATE categories SET slug = NULL"
  end
end
