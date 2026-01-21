class CreateProductAttributeValues < ActiveRecord::Migration[7.1]
  def change
    create_table :product_attribute_values do |t|
      t.references :product_attribute, null: false, foreign_key: true
      t.string :value, null: false
      t.string :slug, null: false
      t.string :color_hex
      t.integer :position
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :product_attribute_values, [:product_attribute_id, :slug], unique: true, name: 'idx_attr_values_on_attr_id_and_slug'
    add_index :product_attribute_values, [:product_attribute_id, :position], name: 'idx_attr_values_on_attr_id_and_position'
  end
end
