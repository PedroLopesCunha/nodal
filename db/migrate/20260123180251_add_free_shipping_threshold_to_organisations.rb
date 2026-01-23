class AddFreeShippingThresholdToOrganisations < ActiveRecord::Migration[7.1]
  def change
    add_column :organisations, :free_shipping_threshold_cents, :integer, default: nil
    add_column :organisations, :free_shipping_threshold_currency, :string, default: "EUR"
  end
end
