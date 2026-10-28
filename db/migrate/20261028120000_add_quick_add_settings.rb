class AddQuickAddSettings < ActiveRecord::Migration[7.1]
  def change
    add_column :organisations, :quick_add_enabled, :boolean, default: false, null: false
    add_column :products, :quick_add_enabled, :boolean, default: true, null: false
  end
end
