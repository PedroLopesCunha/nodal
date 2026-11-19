class CreateProductBundles < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :bundle, :boolean, null: false, default: false
    add_column :products, :bundle_featured, :boolean, null: false, default: false
    add_column :products, :bundle_position, :integer, null: false, default: 0

    create_table :bundle_components do |t|
      t.references :product, null: false, foreign_key: true
      t.references :product_variant, null: false, foreign_key: true
      t.integer :quantity, null: false, default: 1
      t.timestamps
    end
    add_index :bundle_components, [:product_id, :product_variant_id], unique: true
    add_check_constraint :bundle_components, "quantity > 0", name: "bundle_component_positive_quantity"

    create_table :order_bundles do |t|
      t.references :order, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :quantity, null: false, default: 1
      t.integer :unit_price_cents, null: false
      t.jsonb :composition, null: false, default: []
      t.timestamps
    end
    add_check_constraint :order_bundles, "quantity > 0 AND unit_price_cents >= 0", name: "order_bundle_valid_amounts"
    add_reference :order_items, :order_bundle, foreign_key: true
    add_column :order_items, :bundle_amount_cents, :integer
    add_column :order_items, :bundle_component_quantity, :integer
  end
end
