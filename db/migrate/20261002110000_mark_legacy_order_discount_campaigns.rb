class MarkLegacyOrderDiscountCampaigns < ActiveRecord::Migration[7.1]
  def change
    add_column :order_discount_campaigns, :legacy, :boolean, null: false, default: false
    reversible do |direction|
      direction.up { execute "UPDATE order_discount_campaigns SET legacy = true" }
    end
  end
end
