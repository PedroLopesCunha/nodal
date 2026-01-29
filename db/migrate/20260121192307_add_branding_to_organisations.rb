class AddBrandingToOrganisations < ActiveRecord::Migration[7.1]
  def change
    add_column :organisations, :primary_color, :string, default: '#008060'
    add_column :organisations, :secondary_color, :string, default: '#004c3f'
  end
end
