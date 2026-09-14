module CustomerInvitations
  # One empresa as seen by the bulk invitation tool: which of its logins would
  # get an email, and why it can't be invited when none would.
  #
  # Every active login that hasn't accepted and has an address is invited —
  # deactivated logins are left alone. An empresa with an address but no login
  # at all gets one created from its contact details first.
  class Candidate
    # A second email this soon is more likely a double click than a reminder,
    # so these start unticked in the picker.
    RECENT_WINDOW = 48.hours

    attr_reader :customer

    def initialize(customer)
      @customer = customer
    end

    def status
      users.any?(&:invitation_sent_at) ? :pending : :not_invited
    end

    def last_sent_at
      users.filter_map(&:invitation_sent_at).max
    end

    def recently_invited?
      last_sent_at.present? && last_sent_at >= RECENT_WINDOW.ago
    end

    def email_count
      needs_login? ? 1 : invitable_users.size
    end

    def eligible?
      ineligible_reason.nil?
    end

    # :inactive, :accepted, :logins_deactivated or :no_email — nil when eligible.
    def ineligible_reason
      return :inactive unless customer.active?
      return :accepted if users.any?(&:invitation_accepted_at)
      return nil if email_count.positive?
      return :logins_deactivated if users.any? && users.none?(&:active?)

      :no_email
    end

    # Creates the missing login when needed, so call it only when sending.
    def users_to_invite!
      return [] unless eligible?

      if needs_login?
        customer.seed_stub_customer_user
        @users = customer.customer_users.reload.to_a
      end
      invitable_users
    end

    private

    def users
      @users ||= customer.customer_users.to_a
    end

    def invitable_users
      users.select { |user| user.active? && user.invitation_accepted_at.nil? && user.email.present? }
    end

    def needs_login?
      users.empty? && customer.email.present?
    end
  end
end
