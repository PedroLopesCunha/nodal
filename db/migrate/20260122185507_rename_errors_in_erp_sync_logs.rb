class RenameErrorsInErpSyncLogs < ActiveRecord::Migration[7.1]
  def change
    rename_column :erp_sync_logs, :errors, :error_details
  end
end
