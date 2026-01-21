class CreateProductVariants < ActiveRecord::Migration[7.1]
  def change
    create_table :product_variants do |t|
      t.references :organisation, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.string :sku
      t.string :name
      t.integer :unit_price_cents
      t.string :unit_price_currency, default: 'EUR'
      t.integer :stock_quantity, default: 0
      t.boolean :track_stock, default: false, null: false
      t.boolean :available, default: true, null: false
      t.boolean :is_default, default: false, null: false
      t.integer :position

      t.timestamps
    end

    add_index :product_variants, [:organisation_id, :sku], unique: true, where: "sku IS NOT NULL AND sku != ''"
    add_index :product_variants, [:product_id, :is_default]
    add_index :product_variants, [:product_id, :position]
    add_index :product_variants, [:product_id, :available]
  end
end
