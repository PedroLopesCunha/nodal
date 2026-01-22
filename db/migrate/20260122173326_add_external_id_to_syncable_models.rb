class AddExternalIdToSyncableModels < ActiveRecord::Migration[7.1]
  def change
    # Add ERP sync fields to products
    add_column :products, :external_id, :string
    add_column :products, :external_source, :string
    add_column :products, :last_synced_at, :datetime
    add_column :products, :sync_error, :text
    add_index :products, [:organisation_id, :external_id, :external_source],
              unique: true,
              where: "external_id IS NOT NULL",
              name: "index_products_on_org_external_id_source"

    # Add ERP sync fields to customers
    add_column :customers, :external_id, :string
    add_column :customers, :external_source, :string
    add_column :customers, :last_synced_at, :datetime
    add_column :customers, :sync_error, :text
    add_index :customers, [:organisation_id, :external_id, :external_source],
              unique: true,
              where: "external_id IS NOT NULL",
              name: "index_customers_on_org_external_id_source"

    # Add ERP sync fields to product_variants
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
