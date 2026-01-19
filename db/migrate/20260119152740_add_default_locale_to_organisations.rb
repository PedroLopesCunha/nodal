class AddDefaultLocaleToOrganisations < ActiveRecord::Migration[7.1]
  def change
    add_column :organisations, :default_locale, :string, default: 'en', null: false
    add_index :organisations, :default_locale
  end
end
