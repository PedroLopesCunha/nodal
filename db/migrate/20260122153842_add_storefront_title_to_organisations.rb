class AddStorefrontTitleToOrganisations < ActiveRecord::Migration[7.1]
  def change
    add_column :organisations, :storefront_title, :string
  end
end
