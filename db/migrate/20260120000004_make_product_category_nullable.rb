class MakeProductCategoryNullable < ActiveRecord::Migration[7.1]
  def change
    change_column_null :products, :category_id, true
  end
end
