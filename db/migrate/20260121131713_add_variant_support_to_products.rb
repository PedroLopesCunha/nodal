class AddVariantSupportToProducts < ActiveRecord::Migration[7.1]
  def change
    add_column :products, :has_variants, :boolean, default: false, null: false
    add_column :products, :variants_generated, :boolean, default: false, null: false
  end
end
