class AddLocaleToCustomers < ActiveRecord::Migration[7.1]
  def change
    add_column :customers, :locale, :string, default: 'en', null: false
    add_index :customers, :locale
  end
end
