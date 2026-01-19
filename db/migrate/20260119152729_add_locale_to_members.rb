class AddLocaleToMembers < ActiveRecord::Migration[7.1]
  def change
    add_column :members, :locale, :string, default: 'en', null: false
    add_index :members, :locale
  end
end
