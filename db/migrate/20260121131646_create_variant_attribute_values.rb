class CreateVariantAttributeValues < ActiveRecord::Migration[7.1]
  def change
    create_table :variant_attribute_values do |t|
      t.references :product_variant, null: false, foreign_key: true
      t.references :product_attribute_value, null: false, foreign_key: true

      t.timestamps
    end

    add_index :variant_attribute_values, [:product_variant_id, :product_attribute_value_id], unique: true, name: 'idx_variant_attribute_values_unique'
  end
end
