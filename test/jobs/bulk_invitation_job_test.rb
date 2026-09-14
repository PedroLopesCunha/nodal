require "test_helper"

class BulkInvitationJobTest < ActiveJob::TestCase
  setup do
    BulkInvitationJob.send_interval = 0
    ActionMailer::Base.deliveries.clear

    @org = Organisation.create!(name: "Bulk Invite Job Org")
    @member = Member.create!(email: "admin@bulk.local", password: "password123", first_name: "Ad", last_name: "Min")
    @org.org_members.create!(member: @member, role: "owner", active: true)
    @task = @org.background_tasks.create!(member: @member, task_type: "bulk_customer_invitation", status: :pending)
  end

  teardown do
    BulkInvitationJob.send_interval = 0.6
  end

  def customer(name, email: "#{name.parameterize}@empresa.local")
    Customer.create!(organisation: @org, company_name: name, contact_name: name, email: email, active: true)
  end

  def login(customer, label, **attrs)
    CustomerUser.create!(organisation: @org, customer: customer, email: "#{label}@login.local",
                         password: "pass1234", password_confirmation: "pass1234",
                         contact_name: label, active: true, **attrs)
  end

  test "emails every invitable login, skips the rest and records the result" do
    two_logins = customer("Two Logins")
    login(two_logins, "one")
    login(two_logins, "two", invitation_sent_at: 10.days.ago)
    login(two_logins, "off", active: false)
    no_email = customer("No Email", email: "")
    accepted = customer("Accepted Meanwhile")
    login(accepted, "acc", invitation_accepted_at: 1.hour.ago)

    BulkInvitationJob.perform_now(@task.id, organisation_id: @org.id, member_id: @member.id,
                                  customer_ids: [two_logins.id, no_email.id, accepted.id])

    recipients = ActionMailer::Base.deliveries.flat_map(&:to).sort
    assert_equal ["one@login.local", "two@login.local"], recipients

    @task.reload
    assert_equal "completed", @task.status
    assert_equal 3, @task.total
    assert_equal({ "invitations_sent" => 2, "customers_invited" => 1 }, @task.result["stats"])
    assert_equal ["Accepted Meanwhile", "No Email"], @task.result["errors"].map { |e| e["field"] }.sort

    assert login_sent?(two_logins, "one@login.local")
    assert_equal @member, two_logins.customer_users.find_by(email: "one@login.local").invited_by
  end

  test "ignores customers from another organisation" do
    other_org = Organisation.create!(name: "Other Org")
    foreign = Customer.create!(organisation: other_org, company_name: "Foreign", contact_name: "F",
                               email: "foreign@empresa.local", active: true)

    BulkInvitationJob.perform_now(@task.id, organisation_id: @org.id, member_id: @member.id, customer_ids: [foreign.id])

    assert_empty ActionMailer::Base.deliveries
    assert_equal 0, foreign.customer_users.count
  end

  private

  def login_sent?(customer, email)
    customer.customer_users.find_by(email: email).invitation_sent_at.present?
  end
end
