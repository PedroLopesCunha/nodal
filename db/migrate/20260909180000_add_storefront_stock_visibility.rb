class AddStorefrontStockVisibility < ActiveRecord::Migration[7.1]
  def change
    # What the shop is allowed to say about quantities. `none` keeps today's
    # behaviour — in stock or not, and the cart corrects the quantity later.
    add_column :organisations, :storefront_stock_display, :string, null: false, default: "none"

    # Who gets to see them. Kept on the company rather than the login: the
    # trust is extended to the account, and per-login would mean one colleague
    # sees quantities and the next does not. Customer categories are only a way
    # to select companies in bulk, never a live rule — a company reclassified
    # later does not gain access on its own.
    add_column :customers, :sees_stock_quantities, :boolean, null: false, default: false

    add_index :customers, [ :organisation_id, :sees_stock_quantities ],
              name: "index_customers_on_org_and_stock_visibility"
  end
end
