class DropAndRecreateErpTables < ActiveRecord::Migration[7.1]
  def up
    # Drop existing incomplete tables
    drop_table :erp_sync_logs, if_exists: true
    drop_table :erp_configurations, if_exists: true

    # Recreate erp_configurations with all columns
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

    # Recreate erp_sync_logs with all columns
    create_table :erp_sync_logs do |t|
      t.references :organisation, null: false, foreign_key: true
      t.references :erp_configuration, null: false, foreign_key: true
      t.string :sync_type
      t.string :entity_type
      t.string :status
      t.integer :records_processed, default: 0
      t.integer :records_created, default: 0
      t.integer :records_updated, default: 0
      t.integer :records_failed, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.jsonb :errors, default: []
      t.text :summary

      t.timestamps
    end

    add_index :erp_sync_logs, [:organisation_id, :created_at]

    # Add ERP sync fields to products if not exists
    unless column_exists?(:products, :external_id)
      add_column :products, :external_id, :string
      add_column :products, :external_source, :string
      add_column :products, :last_synced_at, :datetime
      add_column :products, :sync_error, :text
      add_index :products, [:organisation_id, :external_id, :external_source],
                unique: true,
                where: "external_id IS NOT NULL",
                name: "index_products_on_org_external_id_source"
    end

    # Add ERP sync fields to customers if not exists
    unless column_exists?(:customers, :external_id)
      add_column :customers, :external_id, :string
      add_column :customers, :external_source, :string
      add_column :customers, :last_synced_at, :datetime
      add_column :customers, :sync_error, :text
      add_index :customers, [:organisation_id, :external_id, :external_source],
                unique: true,
                where: "external_id IS NOT NULL",
                name: "index_customers_on_org_external_id_source"
    end

    # Add ERP sync fields to product_variants if not exists
    unless column_exists?(:product_variants, :external_id)
      add_column :product_variants, :external_id, :string
      add_column :product_variants, :external_source, :string
      add_column :product_variants, :last_synced_at, :datetime
      add_column :product_variants, :sync_error, :text
      add_index :product_variants, [:product_id, :external_id, :external_source],
                unique: true,
                where: "external_id IS NOT NULL",
                name: "index_product_variants_on_product_external_id_source"
    end
  end

  def down
    remove_index :product_variants, name: "index_product_variants_on_product_external_id_source", if_exists: true
    remove_column :product_variants, :sync_error, if_exists: true
    remove_column :product_variants, :last_synced_at, if_exists: true
    remove_column :product_variants, :external_source, if_exists: true
    remove_column :product_variants, :external_id, if_exists: true

    remove_index :customers, name: "index_customers_on_org_external_id_source", if_exists: true
    remove_column :customers, :sync_error, if_exists: true
    remove_column :customers, :last_synced_at, if_exists: true
    remove_column :customers, :external_source, if_exists: true
    remove_column :customers, :external_id, if_exists: true

    remove_index :products, name: "index_products_on_org_external_id_source", if_exists: true
    remove_column :products, :sync_error, if_exists: true
    remove_column :products, :last_synced_at, if_exists: true
    remove_column :products, :external_source, if_exists: true
    remove_column :products, :external_id, if_exists: true

    drop_table :erp_sync_logs, if_exists: true
    drop_table :erp_configurations, if_exists: true
  end
end
