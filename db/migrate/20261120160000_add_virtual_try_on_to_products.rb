class AddVirtualTryOnToProducts < ActiveRecord::Migration[7.1]
  def change
    change_table :products, bulk: true do |t|
      t.boolean :virtual_try_on_enabled, default: false, null: false
      t.string :virtual_try_on_kind, default: "earrings", null: false
      t.decimal :virtual_try_on_height_mm, precision: 7, scale: 2
      t.decimal :virtual_try_on_anchor_x, precision: 5, scale: 4, default: 0.5, null: false
      t.decimal :virtual_try_on_anchor_y, precision: 5, scale: 4, default: 0.5, null: false
    end
  end
end
