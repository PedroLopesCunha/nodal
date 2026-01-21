class CreateProductAttributes < ActiveRecord::Migration[7.1]
  def change
    create_table :product_attributes do |t|
      t.references :organisation, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug, null: false
      t.integer :position
      t.boolean :active, default: true, null: false
      t.datetime :discarded_at

      t.timestamps
    end

    add_index :product_attributes, [:organisation_id, :slug], unique: true
    add_index :product_attributes, [:organisation_id, :position]
    add_index :product_attributes, :discarded_at
  end
end
