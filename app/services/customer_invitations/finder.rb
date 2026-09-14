module CustomerInvitations
  # The empresas the bulk invitation picker offers: active, with no accepted
  # login yet ("Por convidar" and "Pendentes" on the customers page), narrowed
  # by the picker's filters. Invitable ones come first, the rest after so it's
  # visible why they were left out.
  class Finder
    STATUSES = %w[not_invited pending all].freeze

    def initialize(organisation:, status: "not_invited", sent_from: nil, sent_to: nil, rep: nil, query: nil)
      @organisation = organisation
      @status = STATUSES.include?(status) ? status : "not_invited"
      @sent_from = parse_date(sent_from)
      @sent_to = parse_date(sent_to)
      @rep = rep
      @query = query
    end

    def candidates
      scope.map { |customer| Candidate.new(customer) }
           .sort_by { |candidate| [candidate.eligible? ? 0 : 1, candidate.customer.company_name.to_s.downcase] }
    end

    private

    def scope
      accepted_ids = CustomerUser.where.not(invitation_accepted_at: nil).select(:customer_id)
      invited_ids = CustomerUser.where.not(invitation_sent_at: nil).select(:customer_id)

      scope = @organisation.customers.where(active: true).where.not(id: accepted_ids)
      scope = scope.where(id: invited_ids) if @status == "pending"
      scope = scope.where.not(id: invited_ids) if @status == "not_invited"
      scope = filter_by_sent_date(scope)
      scope = filter_by_rep(scope)
      scope = filter_by_query(scope)
      scope.includes(:customer_users, customer_assignment: { org_member: :member })
    end

    # By the latest invitation, since a resend replaces the link the customer
    # was sent before.
    def filter_by_sent_date(scope)
      return scope unless @sent_from || @sent_to

      last_sent = CustomerUser.group(:customer_id)
      last_sent = last_sent.having("MAX(invitation_sent_at) >= ?", @sent_from.beginning_of_day) if @sent_from
      last_sent = last_sent.having("MAX(invitation_sent_at) <= ?", @sent_to.end_of_day) if @sent_to
      scope.where(id: last_sent.select(:customer_id))
    end

    def filter_by_rep(scope)
      case @rep.to_s
      when "none"
        scope.where.not(id: CustomerAssignment.select(:customer_id))
      when /\A\d+\z/
        scope.where(id: CustomerAssignment.where(org_member_id: @rep).select(:customer_id))
      else
        scope
      end
    end

    def filter_by_query(scope)
      return scope if @query.blank?

      scope.where(
        "unaccent(company_name) ILIKE unaccent(:q) OR unaccent(contact_name) ILIKE unaccent(:q) " \
        "OR unaccent(customers.email) ILIKE unaccent(:q) OR unaccent(external_id) ILIKE unaccent(:q)",
        q: "%#{ActiveRecord::Base.sanitize_sql_like(@query.to_s.strip)}%"
      )
    end

    def parse_date(value)
      Date.iso8601(value.to_s)
    rescue Date::Error
      nil
    end
  end
end
