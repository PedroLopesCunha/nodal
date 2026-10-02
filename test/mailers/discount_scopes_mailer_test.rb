require "test_helper"

class DiscountScopesMailerTest < ActionMailer::TestCase
  test "multicategory product campaigns render the product template rather than the order template" do
    org = Organisation.create!(name: "Mail scopes", email_discount_notification_enabled: true)
    customer = org.customers.create!(company_name: "Buyer", contact_name: "J", active: true, email: "buyer@example.test")
    categories = %w[Prata Bilaminado].map { |name| org.categories.create!(name: name) }
    discount = org.product_discounts.build(discount_type: 'percentage', discount_value: 0.08, name: 'Outubro', min_quantity: 1)
    discount.configure_category_scopes(mode: 'include', category_ids: categories.map(&:id))
    discount.save!
    email = CustomerMailer.with(discount: discount, organisation: org).notify_clients_about_discount
    assert_includes email.html_part.body.to_s, 'Apenas: Prata, Bilaminado'
    assert_includes email.text_part.body.to_s, 'Outubro'
    assert_not_includes email.html_part.body.to_s, 'Escalões existentes'
  end
end
