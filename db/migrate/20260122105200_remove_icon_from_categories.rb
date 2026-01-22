class RemoveIconFromCategories < ActiveRecord::Migration[7.1]
  def change
    remove_column :categories, :icon, :string
  end
end
