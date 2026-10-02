class CreateDiscountCategoryScopes < ActiveRecord::Migration[7.1]
  def up
    create_table :order_discount_campaigns do |t|
      t.references :organisation, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :priority, null: false
      t.timestamps
    end
    add_index :order_discount_campaigns, [:organisation_id, :priority], unique: true, name: "idx_order_campaign_priority"
    add_check_constraint :order_discount_campaigns, "priority > 0", name: "order_campaign_positive_priority"
    add_reference :order_discounts, :order_discount_campaign, foreign_key: true
    add_column :product_discounts, :name, :string
    add_column :customer_product_discounts, :name, :string
    add_column :orders, :auto_discount_scope_snapshot, :jsonb
    add_column :order_items, :auto_order_discount_amount_cents, :integer

    create_table :discount_category_scopes do |t|
      t.references :organisation, null: false, foreign_key: true
      t.references :product_discount, foreign_key: true
      t.references :customer_product_discount, foreign_key: true, index: { name: "idx_scope_customer_discount" }
      t.references :order_discount_campaign, foreign_key: true, index: { name: "idx_scope_order_campaign" }
      t.string :role, null: false
      t.string :mode, null: false
      t.timestamps
    end
    add_check_constraint :discount_category_scopes,
      "num_nonnulls(product_discount_id, customer_product_discount_id, order_discount_campaign_id) = 1", name: "discount_scope_one_owner"
    add_check_constraint :discount_category_scopes, "role IN ('qualification', 'discount')", name: "discount_scope_role"
    add_check_constraint :discount_category_scopes, "mode IN ('all', 'include', 'exclude')", name: "discount_scope_mode"
    %w[product_discount customer_product_discount order_discount_campaign].each do |owner|
      add_index :discount_category_scopes, ["#{owner}_id", :role], unique: true,
        where: "#{owner}_id IS NOT NULL", name: "idx_scope_#{owner}_role"
    end
    create_table :discount_category_scope_categories do |t|
      t.references :discount_category_scope, null: false, foreign_key: true, index: { name: "idx_scope_category_scope" }
      t.references :category, null: false, foreign_key: true
      t.timestamps
    end
    add_index :discount_category_scope_categories, [:discount_category_scope_id, :category_id], unique: true, name: "idx_scope_category_unique"
    backfill
  end

  def backfill
    execute <<~SQL
      INSERT INTO order_discount_campaigns (organisation_id, name, priority, created_at, updated_at)
      SELECT DISTINCT organisation_id, 'Escalões existentes', 1, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
      FROM order_discounts
      ON CONFLICT (organisation_id, priority) DO NOTHING;
      UPDATE order_discounts d SET order_discount_campaign_id = c.id
      FROM order_discount_campaigns c
      WHERE c.organisation_id = d.organisation_id AND c.priority = 1
        AND d.order_discount_campaign_id IS NULL;
    SQL
    %w[product_discount customer_product_discount order_discount_campaign].each do |owner|
      category = owner == "order_discount_campaign" ? "NULL::bigint" : "d.category_id"
      execute <<~SQL
        INSERT INTO discount_category_scopes (organisation_id, #{owner}_id, role, mode, created_at, updated_at)
        SELECT d.organisation_id, d.id, roles.role,
          CASE WHEN #{category} IS NULL THEN 'all' ELSE 'include' END,
          CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM #{owner.pluralize} d CROSS JOIN (VALUES ('qualification'), ('discount')) AS roles(role)
        WHERE NOT EXISTS (SELECT 1 FROM discount_category_scopes s WHERE s.#{owner}_id = d.id AND s.role = roles.role);
      SQL
      next if owner == "order_discount_campaign"
      execute <<~SQL
        INSERT INTO discount_category_scope_categories (discount_category_scope_id, category_id, created_at, updated_at)
        SELECT s.id, d.category_id, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP
        FROM discount_category_scopes s JOIN #{owner.pluralize} d ON d.id = s.#{owner}_id
        WHERE d.category_id IS NOT NULL
        ON CONFLICT (discount_category_scope_id, category_id) DO NOTHING;
      SQL
    end
  end

  def down
    if select_value("SELECT EXISTS (SELECT 1 FROM discount_category_scopes WHERE mode = 'exclude')")
      raise ActiveRecord::IrreversibleMigration, "Category exclusions cannot be represented by the legacy schema"
    end
    drop_table :discount_category_scope_categories
    drop_table :discount_category_scopes
    remove_reference :order_discounts, :order_discount_campaign, foreign_key: true
    drop_table :order_discount_campaigns
    remove_column :product_discounts, :name
    remove_column :customer_product_discounts, :name
    remove_column :orders, :auto_discount_scope_snapshot
    remove_column :order_items, :auto_order_discount_amount_cents
  end
end
