class CreateErpSyncLogs < ActiveRecord::Migration[7.1]
  def change
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
  end
end
