class AddActiveToAddresses < ActiveRecord::Migration[7.1]
  def change
    add_column :addresses, :active, :boolean, default: true, null: false
  end
end
