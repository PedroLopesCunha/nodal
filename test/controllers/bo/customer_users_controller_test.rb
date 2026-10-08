require "test_helper"

class Bo::CustomerUsersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @org = Organisation.create!(name: "Login Invite Org", currency: "EUR")
    member = Member.create!(email: "login-invite-admin@example.com", password: "password123", first_name: "Ana", last_name: "Admin")
    @org.org_members.create!(member: member, role: "owner", active: true)
    @customer = @org.customers.create!(company_name: "Client", contact_name: "Ana", active: true)
    sign_in member
  end

  test "new login submitted by Turbo returns to customer logins with the standard success flash" do
    post bo_customer_customer_users_path(org_slug: @org.slug, customer_id: @customer.id),
      params: { customer_user: { email: "new-login@example.com", contact_name: "Ana" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }
    assert_response :see_other
    assert_redirected_to bo_customer_path(org_slug: @org.slug, id: @customer.id, anchor: "logins")
    assert @customer.customer_users.find_by!(email: "new-login@example.com").invitation_sent_at
    follow_redirect!
    assert_response :success
    assert_select "#logins", count: 1
    assert_select ".flash-container .alert-success .alert-message", text: I18n.t("bo.customer_users.flash.invited", email: "new-login@example.com")
  end

  test "creating a login in the modal still updates the modal frame" do
    post bo_customer_customer_users_path(org_slug: @org.slug, customer_id: @customer.id),
      params: { logins_modal: "1", customer_user: { email: "modal-login@example.com" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_select "turbo-stream[action=update][target='customer-logins-frame-#{@customer.id}']", count: 1
  end

  test "invalid new login stays on the form with validation errors" do
    post bo_customer_customer_users_path(org_slug: @org.slug, customer_id: @customer.id),
      params: { customer_user: { email: "invalid" } },
      headers: { "Accept" => "text/vnd.turbo-stream.html, text/html" }
    assert_response :unprocessable_entity
    assert_select "#new-customer-user-form .alert-danger", count: 1
  end
end
