require "test_helper"

class CustomerTest < ActiveSupport::TestCase
  test "export login_emails column joins the customer's login emails" do
    org = Organisation.create!(name: "Export Org")
    customer = Customer.create!(organisation: org, company_name: "Acme", contact_name: "J", active: true)
    CustomerUser.create!(organisation: org, customer: customer, email: "a@acme.test",
      password: "password123", password_confirmation: "password123", contact_name: "A", active: true)
    CustomerUser.create!(organisation: org, customer: customer, email: "b@acme.test",
      password: "password123", password_confirmation: "password123", contact_name: "B", active: true)

    col = Customer.exportable_columns.find { |c| c[:key] == :login_emails }
    assert col, "login_emails export column should exist"
    assert col[:default], "login_emails should be exported by default"
    assert_equal "a@acme.test; b@acme.test", col[:value].call(customer.reload)

    # The legacy Customer#email orphan column is no longer a default export.
    email_col = Customer.exportable_columns.find { |c| c[:key] == :email }
    assert_not email_col[:default]
  end
end
