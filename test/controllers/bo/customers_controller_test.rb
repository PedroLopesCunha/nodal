require "test_helper"

class Bo::CustomersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @organisation = Organisation.create!(name: "Customers Filter Org", currency: "EUR")
    @member = Member.create!(
      email: "customers-filter@example.com",
      password: "password123",
      first_name: "Filter",
      last_name: "Tester"
    )
    @organisation.org_members.create!(member: @member, role: "owner", active: true)
    sign_in @member

    @uninvited_with_email    = build_customer("Uninvited With Email", email: "with@empresa.local")
    @uninvited_without_email = build_customer("Uninvited Without Email", email: "")
    @accepted_never_sent     = build_customer("Accepted Never Sent", email: "accepted@empresa.local")
    build_user(@accepted_never_sent, "accepted", invitation_accepted_at: 1.day.ago)
    @pending                 = build_customer("Pending Invite", email: "pending@empresa.local")
    build_user(@pending, "pending", invitation_sent_at: 1.day.ago)
  end

  def build_customer(name, email:)
    Customer.create!(organisation: @organisation, company_name: name, contact_name: name,
                     email: email, active: true)
  end

  def build_user(customer, label, **attrs)
    CustomerUser.create!(organisation: @organisation, customer: customer,
                         email: "#{label}@login.local", password: "pass1234",
                         password_confirmation: "pass1234", contact_name: label,
                         active: true, **attrs)
  end

  def listed_names(**params)
    get bo_customers_path(org_slug: @organisation.slug, **params)
    assert_response :success
    [@uninvited_with_email, @uninvited_without_email, @accepted_never_sent, @pending]
      .map(&:company_name).select { |name| response.body.include?(name) }
  end

  test "not_invited excludes customers whose login was accepted without an invite" do
    assert_equal ["Uninvited With Email", "Uninvited Without Email"], listed_names(status: "not_invited")
  end

  test "email filter narrows not_invited to those with or without email" do
    assert_equal ["Uninvited With Email"], listed_names(status: "not_invited", email: "with")
    assert_equal ["Uninvited Without Email"], listed_names(status: "not_invited", email: "without")
  end

  def build_rep(first_name, is_sales_rep: true)
    member = Member.create!(email: "#{first_name.downcase}@reps.local", password: "password123",
                            first_name: first_name, last_name: "Rep")
    @organisation.org_members.create!(member: member, role: "member", active: true, is_sales_rep: is_sales_rep)
  end

  test "rep filter lists a rep's carteira, or customers with no rep" do
    rep = build_rep("Joana")
    CustomerAssignment.create!(org_member: rep, customer: @pending)
    CustomerAssignment.create!(org_member: rep, customer: @uninvited_with_email)

    assert_equal ["Uninvited With Email", "Pending Invite"], listed_names(rep: rep.id)
    assert_select "select[name=rep] option[selected][value=?]", rep.id.to_s
    assert_select ".badge", text: /Joana Rep/

    assert_equal ["Uninvited Without Email", "Accepted Never Sent"], listed_names(rep: "none")
  end

  test "rep filter combines with status" do
    rep = build_rep("Joana")
    CustomerAssignment.create!(org_member: rep, customer: @pending)
    CustomerAssignment.create!(org_member: rep, customer: @uninvited_with_email)

    assert_equal ["Uninvited With Email"], listed_names(rep: rep.id, status: "not_invited")
    assert_equal ["Uninvited Without Email"], listed_names(rep: "none", status: "not_invited")
  end

  test "rep options include members who lost the rep flag but still hold customers" do
    build_rep("Current")
    former = build_rep("Former", is_sales_rep: false)
    CustomerAssignment.create!(org_member: former, customer: @pending)
    build_rep("Never", is_sales_rep: false)

    get bo_customers_path(org_slug: @organisation.slug)
    options = css_select("select[name=rep] option").map(&:text)

    assert_includes options, "Current Rep"
    assert_includes options, "Former Rep"
    assert_not_includes options, "Never Rep"
  end

  test "email filter works on its own" do
    assert_equal ["Uninvited With Email", "Accepted Never Sent", "Pending Invite"], listed_names(email: "with")
    assert_equal ["Uninvited Without Email"], listed_names(email: "without")
  end
end
