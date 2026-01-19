class MakeLocaleNullable < ActiveRecord::Migration[7.1]
  def change
    # Make Member locale nullable
    change_column_null :members, :locale, true
    change_column_default :members, :locale, from: 'en', to: nil

    # Make Customer locale nullable
    change_column_null :customers, :locale, true
    change_column_default :customers, :locale, from: 'en', to: nil

    # Reset all 'en' values to nil (treat as "no preference set")
    # This allows them to fall back to organisation default
    Member.where(locale: 'en').update_all(locale: nil)
    Customer.where(locale: 'en').update_all(locale: nil)
  end
end
