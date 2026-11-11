class AddShowProductCategoryOnCardToOrganisations < ActiveRecord::Migration[7.1]
  def change
    add_column :organisations, :show_product_category_on_card, :boolean, default: true, null: false
  end
end
