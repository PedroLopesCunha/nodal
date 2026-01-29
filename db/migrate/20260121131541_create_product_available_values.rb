class CreateProductAvailableValues < ActiveRecord::Migration[7.1]
  def change
    create_table :product_available_values do |t|
      t.references :product, null: false, foreign_key: true
      t.references :product_attribute_value, null: false, foreign_key: true

      t.timestamps
    end

    add_index :product_available_values, [:product_id, :product_attribute_value_id], unique: true, name: 'idx_product_available_values_unique'
  end
end
