class AddContactFieldsToOrganisations < ActiveRecord::Migration[7.1]
  def change
    add_column :organisations, :contact_email, :string
    add_column :organisations, :phone, :string
    add_column :organisations, :whatsapp, :string
    add_column :organisations, :business_hours, :text
    add_column :organisations, :use_billing_address_for_contact, :boolean, default: true, null: false
  end
end
