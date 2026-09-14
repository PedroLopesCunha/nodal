require "test_helper"

class CustomerInvitations::FinderTest < ActiveSupport::TestCase
  setup do
    @org = Organisation.create!(name: "Bulk Invite Finder Org")
  end

  def customer(name, email: "#{name.parameterize}@empresa.local", active: true)
    Customer.create!(organisation: @org, company_name: name, contact_name: name, email: email, active: active)
  end

  def login(customer, label, **attrs)
    CustomerUser.create!(organisation: @org, customer: customer, email: "#{label}@login.local",
                         password: "pass1234", password_confirmation: "pass1234",
                         contact_name: label, active: true, **attrs)
  end

  def names(**filters)
    CustomerInvitations::Finder.new(organisation: @org, **filters).candidates.map { |c| c.customer.company_name }
  end

  test "offers active customers with no accepted login, split by status" do
    login(customer("Never Invited"), "never")
    login(customer("Pending"), "pending", invitation_sent_at: 3.days.ago)
    login(customer("Accepted"), "accepted", invitation_sent_at: 3.days.ago, invitation_accepted_at: 2.days.ago)
    customer("Inactive", active: false)

    assert_equal ["Never Invited"], names(status: "not_invited")
    assert_equal ["Pending"], names(status: "pending")
    assert_equal ["Never Invited", "Pending"], names(status: "all")
  end

  test "filters pending customers by their latest invitation date" do
    login(customer("Early"), "early", invitation_sent_at: Time.zone.parse("2026-08-01 10:00"))
    login(customer("Mid"), "mid", invitation_sent_at: Time.zone.parse("2026-08-15 23:30"))
    resent = customer("Resent")
    login(resent, "resent-old", invitation_sent_at: Time.zone.parse("2026-08-02 10:00"))
    login(resent, "resent-new", invitation_sent_at: Time.zone.parse("2026-09-01 10:00"))

    assert_equal ["Mid"], names(status: "pending", sent_from: "2026-08-10", sent_to: "2026-08-15")
    assert_equal ["Early"], names(status: "pending", sent_to: "2026-08-10")
    assert_equal ["Mid", "Resent"], names(status: "pending", sent_from: "2026-08-10")
  end

  test "filters by rep and search" do
    member = Member.create!(email: "rep@reps.local", password: "password123", first_name: "Rita", last_name: "Rep")
    rep = @org.org_members.create!(member: member, role: "member", active: true, is_sales_rep: true)
    CustomerAssignment.create!(org_member: rep, customer: customer("Ourivesaria Sé"))
    customer("Joalharia Norte")

    assert_equal ["Ourivesaria Sé"], names(status: "all", rep: rep.id.to_s)
    assert_equal ["Joalharia Norte"], names(status: "all", rep: "none")
    assert_equal ["Ourivesaria Sé"], names(status: "all", query: "ourivesaria se")
  end

  test "ineligible customers come after the invitable ones" do
    customer("A Without Email", email: "")
    login(customer("B With Login"), "b")

    candidates = CustomerInvitations::Finder.new(organisation: @org, status: "all").candidates
    assert_equal ["B With Login", "A Without Email"], candidates.map { |c| c.customer.company_name }
  end
end
