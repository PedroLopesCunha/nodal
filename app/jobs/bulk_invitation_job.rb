class BulkInvitationJob < ApplicationJob
  include Trackable

  queue_as :default

  # Resend accepts 2 requests per second; going faster fails the extra sends.
  class_attribute :send_interval, default: 0.6

  def perform(task_id, organisation_id:, member_id:, customer_ids:)
    find_task(task_id)
    organisation = Organisation.find(organisation_id)
    member = Member.find(member_id)
    customers = organisation.customers.where(id: customer_ids).includes(:customer_users).order(:company_name).to_a

    update_progress(0, customers.size)
    sent = 0
    invited_customers = 0
    errors = []

    customers.each_with_index do |customer, index|
      # Checked again here: the picker is a snapshot, and a login may have been
      # accepted or deactivated since.
      candidate = CustomerInvitations::Candidate.new(customer)
      if candidate.eligible?
        delivered = candidate.users_to_invite!.count do |user|
          invite(user, member, errors)
        end
        sent += delivered
        invited_customers += 1 if delivered.positive?
      else
        errors << { field: customer.company_name,
                    message: I18n.t("bo.bulk_invitations.ineligible.#{candidate.ineligible_reason}") }
      end

      update_progress(index + 1)
    end

    save_result({ stats: { invitations_sent: sent, customers_invited: invited_customers }, errors: errors })
  end

  private

  # Same as the per-login "Reenviar" button. A resend replaces the previous link.
  def invite(user, member, errors)
    user.invited_by = member
    user.invite!
    sleep(send_interval) if send_interval.positive?

    return true if user.errors.empty?

    errors << { field: "#{user.customer.company_name} (#{user.email})", message: user.errors.full_messages.to_sentence }
    false
  rescue StandardError => e
    errors << { field: "#{user.customer.company_name} (#{user.email})", message: e.message }
    false
  end
end
