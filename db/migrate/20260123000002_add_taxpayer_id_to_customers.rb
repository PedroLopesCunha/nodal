class AddTaxpayerIdToCustomers < ActiveRecord::Migration[7.1]
  def change
    add_column :customers, :taxpayer_id, :string
  end
end
