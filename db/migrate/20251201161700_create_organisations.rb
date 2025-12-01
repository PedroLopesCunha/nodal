class CreateOrganisations < ActiveRecord::Migration[7.1]
  def change
    create_table :organisations do |t|
      t.string :name
      t.string :slug, null: false
      t.string :billing_email
      t.boolean :active, default: true, null: false

      t.timestamps
    end

    add_index :organisations, :slug, unique: true
  end
end
