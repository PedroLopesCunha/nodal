class EnhanceCategoriesTable < ActiveRecord::Migration[7.1]
  def change
    add_column :categories, :ancestry, :string
    add_column :categories, :ancestry_depth, :integer, default: 0
    add_column :categories, :position, :integer
    add_column :categories, :discarded_at, :datetime
    add_column :categories, :description, :text
    add_column :categories, :icon, :string
    add_column :categories, :color, :string
    add_column :categories, :metadata, :jsonb, default: {}
    add_column :categories, :slug, :string

    add_index :categories, :ancestry
    add_index :categories, :discarded_at
    add_index :categories, [:organisation_id, :slug], unique: true
    add_index :categories, [:organisation_id, :ancestry, :position]
  end
end
