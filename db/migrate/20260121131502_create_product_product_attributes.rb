class CreateProductProductAttributes < ActiveRecord::Migration[7.1]
  def change
    create_table :product_product_attributes do |t|
      t.references :product, null: false, foreign_key: true
      t.references :product_attribute, null: false, foreign_key: true
      t.integer :position

      t.timestamps
    end

    add_index :product_product_attributes, [:product_id, :product_attribute_id], unique: true, name: 'idx_product_product_attributes_unique'
  end
end
