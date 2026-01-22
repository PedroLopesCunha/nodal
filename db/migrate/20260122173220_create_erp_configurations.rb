class CreateErpConfigurations < ActiveRecord::Migration[7.1]
  def change
    create_table :erp_configurations do |t|
      t.references :organisation, null: false, foreign_key: true, index: { unique: true }
      t.boolean :enabled, default: false
      t.string :adapter_type
      t.text :credentials_ciphertext
      t.boolean :sync_products, default: true
      t.boolean :sync_customers, default: true
      t.boolean :sync_orders, default: false
      t.string :sync_frequency, default: 'daily'
      t.datetime :last_sync_at
      t.string :last_sync_status
      t.text :last_sync_error

      t.timestamps
    end
  end
end
