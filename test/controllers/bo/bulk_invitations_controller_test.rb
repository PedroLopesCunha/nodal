require "test_helper"

class Bo::BulkInvitationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers
  include ActiveJob::TestHelper

  setup do
    @organisation = Organisation.create!(name: "Bulk Invite Controller Org", currency: "EUR")
    @owner = member_with_role("owner")
    @uninvited = Customer.create!(organisation: @organisation, company_name: "Uninvited Co", contact_name: "U",
                                  email: "uninvited@empresa.local", active: true)
    @recent = Customer.create!(organisation: @organisation, company_name: "Recent Co", contact_name: "R",
                               email: "recent@empresa.local", active: true)
    CustomerUser.create!(organisation: @organisation, customer: @recent, email: "recent@login.local",
                         password: "pass1234", password_confirmation: "pass1234", contact_name: "R",
                         active: true, invitation_sent_at: 2.hours.ago)
    @no_email = Customer.create!(organisation: @organisation, company_name: "No Email Co", contact_name: "N",
                                 email: "", active: true)
  end

  def member_with_role(role, rep: false)
    member = Member.create!(email: "#{role}-#{SecureRandom.hex(3)}@bulk.local", password: "password123",
                            first_name: role.capitalize, last_name: "Tester")
    @organisation.org_members.create!(member: member, role: role, active: true, is_sales_rep: rep)
    member
  end

  test "customers page shows the button and modal to owners" do
    sign_in @owner
    get bo_customers_path(org_slug: @organisation.slug)

    assert_response :success
    assert_select "a[data-bs-target='#bulkInvitationModal']"
    assert_select "#bulkInvitationModal turbo-frame#bulk_invitation_picker"
  end

  test "picker ticks invitable customers, leaves recent ones unticked and disables the rest" do
    sign_in @owner
    get new_bo_bulk_invitation_path(org_slug: @organisation.slug, status: "all")

    assert_response :success
    assert_select "input[name='customer_ids[]'][value='#{@uninvited.id}'][checked]"
    assert_select "input[name='customer_ids[]'][value='#{@recent.id}']:not([checked])"
    assert_select "input[name='customer_ids[]'][value='#{@no_email.id}'][disabled]"
    assert_select "label:has(input[value='#{@recent.id}']) .fa-clock-rotate-left"
    assert_select "label:has(input[value='#{@uninvited.id}']) .fa-clock-rotate-left", count: 0
  end

  test "sending creates a task and queues the job with this organisation's customers only" do
    sign_in @owner
    foreign = Customer.create!(organisation: Organisation.create!(name: "Elsewhere"), company_name: "Foreign",
                               contact_name: "F", email: "f@empresa.local", active: true)

    assert_enqueued_jobs 1, only: BulkInvitationJob do
      post bo_bulk_invitation_path(org_slug: @organisation.slug), params: { customer_ids: [@uninvited.id, foreign.id] }
    end

    task = @organisation.background_tasks.last
    assert_equal "bulk_customer_invitation", task.task_type
    assert_redirected_to bo_background_task_path(org_slug: @organisation.slug, id: task.id)
    job = enqueued_jobs.find { |j| j["job_class"] == "BulkInvitationJob" }
    assert_equal [@uninvited.id], job["arguments"].last["customer_ids"]
  end

  test "sending nothing goes back with a message" do
    sign_in @owner

    assert_no_enqueued_jobs do
      post bo_bulk_invitation_path(org_slug: @organisation.slug), params: { customer_ids: [] }
    end
    assert_redirected_to bo_customers_path(org_slug: @organisation.slug)
  end

  test "admins only: a sales rep sees no button and can't send" do
    rep = member_with_role("member", rep: true)
    sign_in rep

    get bo_customers_path(org_slug: @organisation.slug)
    assert_select "a[data-bs-target='#bulkInvitationModal']", count: 0

    assert_no_enqueued_jobs do
      assert_raises(Pundit::NotAuthorizedError) do
        post bo_bulk_invitation_path(org_slug: @organisation.slug), params: { customer_ids: [@uninvited.id] }
      end
    end
  end
end
