require "test_helper"

class CustomerInvitations::CandidateTest < ActiveSupport::TestCase
  setup do
    @org = Organisation.create!(name: "Bulk Invite Candidate Org")
  end

  def customer(email: "empresa@empresa.local", active: true)
    Customer.create!(organisation: @org, company_name: "Empresa", contact_name: "Contacto", email: email, active: active)
  end

  def login(customer, label, **attrs)
    CustomerUser.create!(organisation: @org, customer: customer, email: "#{label}@login.local",
                         password: "pass1234", password_confirmation: "pass1234",
                         contact_name: label, active: true, **attrs)
  end

  def candidate(customer)
    CustomerInvitations::Candidate.new(customer.reload)
  end

  test "invites every active login that hasn't accepted, leaving deactivated ones out" do
    c = customer
    first = login(c, "first")
    second = login(c, "second", invitation_sent_at: 5.days.ago)
    login(c, "deactivated", active: false)

    result = candidate(c)
    assert result.eligible?
    assert_equal :pending, result.status
    assert_equal 2, result.email_count
    assert_equal [first, second].map(&:id).sort, result.users_to_invite!.map(&:id).sort
  end

  test "reasons a customer can't be invited" do
    assert_equal :no_email, candidate(customer(email: "")).ineligible_reason

    all_off = customer(email: "off@empresa.local")
    login(all_off, "off", active: false)
    assert_equal :logins_deactivated, candidate(all_off).ineligible_reason

    accepted = customer(email: "acc@empresa.local")
    login(accepted, "acc", invitation_accepted_at: 1.day.ago)
    assert_equal :accepted, candidate(accepted).ineligible_reason

    assert_equal :inactive, candidate(customer(email: "inactive@empresa.local", active: false)).ineligible_reason
  end

  test "a customer with an email but no login gets one created when sending" do
    c = customer(email: "nologin@empresa.local")

    result = candidate(c)
    assert result.eligible?
    assert_equal 1, result.email_count

    users = result.users_to_invite!
    assert_equal ["nologin@empresa.local"], users.map(&:email)
    assert_equal 1, c.customer_users.count
  end

  test "recently invited within 48 hours" do
    recent = customer(email: "recent@empresa.local")
    login(recent, "recent", invitation_sent_at: 47.hours.ago)
    old = customer(email: "old@empresa.local")
    login(old, "old", invitation_sent_at: 49.hours.ago)

    assert candidate(recent).recently_invited?
    assert_not candidate(old).recently_invited?
  end
end
