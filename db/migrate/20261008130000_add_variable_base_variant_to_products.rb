class AddVariableBaseVariantToProducts < ActiveRecord::Migration[7.1]
  def change
    add_reference :products, :variable_base_variant, foreign_key: { to_table: :product_variants, on_delete: :nullify }
  end
end
