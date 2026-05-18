class AddUniqueTaxpayerIdToCustomers < ActiveRecord::Migration[7.1]
  # Partial unique index: enforces NIF uniqueness per organisation, but allows
  # multiple customers with NULL or empty taxpayer_id (historical data has
  # blank NIFs that we don't want to backfill in this PR).
  def change
    add_index :customers,
              [:organisation_id, :taxpayer_id],
              unique: true,
              where: "taxpayer_id IS NOT NULL AND taxpayer_id <> ''",
              name: "index_customers_on_org_id_taxpayer_id_unique"
  end
end
