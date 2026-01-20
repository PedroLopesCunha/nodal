class CreateCategoryProducts < ActiveRecord::Migration[7.1]
  def change
    create_table :category_products do |t|
      t.references :category, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.integer :position

      t.timestamps
    end

    add_index :category_products, [:category_id, :product_id], unique: true
  end
end
