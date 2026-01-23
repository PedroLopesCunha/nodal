class AddTaxpayerIdToOrganisations < ActiveRecord::Migration[7.1]
  def change
    add_column :organisations, :taxpayer_id, :string
  end
end
