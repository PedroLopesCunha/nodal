class Bo::CustomersController < Bo::BaseController
  include Exportable

  before_action :set_and_authorize_customer, only: [:show, :edit, :update, :destroy]

  def index
    @tab = params[:tab] || 'customers'
    @customer_categories = current_organisation.customer_categories.ordered

    # Always call policy_scope to satisfy Pundit's verify_policy_scoped
    load_customers
  end

  def show
    placed_orders = @customer.orders.placed.order(placed_at: :desc).includes(:order_items, :organisation)
    @total_orders = placed_orders.count
    currency = current_organisation.currency
    if @total_orders > 0
      total_cents = placed_orders.sum { |o| o.grand_total.cents }
      @total_spent = Money.new(total_cents, currency)
      @average_order_value = Money.new(total_cents / @total_orders, currency)
    else
      @total_spent = Money.new(0, currency)
      @average_order_value = Money.new(0, currency)
    end
    @last_order = placed_orders.first
    @recent_orders = placed_orders.limit(5)
    @open_cart = @customer.orders.draft.includes(:order_items).first
  end

  def new
    @customer = Customer.new
    @customer.build_billing_address_with_archived(address_type: "billing")
    @customer.shipping_addresses_with_archived.build(address_type: "shipping")
    @customer_categories = current_organisation.customer_categories.ordered
    authorize @customer
  end

  def create
    @customer = Customer.new(customer_params)
    @customer.organisation = current_organisation
    @customer.created_by_member = current_org_member
    # Pure reps don't see the "active" toggle (it's locked to org default), so
    # the field is stripped from params — backfill the boolean here to satisfy
    # the model validation (inclusion: in [true, false]).
    @customer.active = true if @customer.active.nil?
    authorize @customer
    if @customer.save
      # Sales reps creating a customer auto-claim it for their carteira.
      # Owners/admins who are also reps can self-assign explicitly via the
      # assignment UX — we don't auto-grab on their behalf here, since they
      # may be creating on behalf of a different rep.
      if pure_sales_rep?
        CustomerAssignment.create!(org_member: current_org_member, customer: @customer)
      end
      redirect_to bo_customer_path(params[:org_slug], @customer), notice: "Customer created successfully."
    else
      @customer.build_billing_address_with_archived(address_type: "billing") if @customer.billing_address_with_archived.nil?
      @customer.shipping_addresses_with_archived.build(address_type: "shipping") if @customer.shipping_addresses_with_archived.empty?
      @customer_categories = current_organisation.customer_categories.ordered
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @customer = Customer.find(params[:id])
    @customer_categories = current_organisation.customer_categories.ordered
    @customer.build_billing_address_with_archived if @customer.billing_address_with_archived.nil?
    @customer.shipping_addresses_with_archived.build if @customer.shipping_addresses_with_archived.empty?
  end

  def update
    attrs = customer_params.to_h
    # When an admin manually fills external_id (the "Marcar sincronizado"
    # flow), tag the source so future ERP syncs treat the row consistently
    # with auto-imported customers.
    if attrs["external_id"].present? && @customer.external_id.blank?
      attrs["external_source"] = current_organisation.erp_configuration&.adapter_type.presence || "manual"
      attrs["last_synced_at"] = Time.current
    end
    if @customer.update(attrs)
      @customer.reload
      msg = if attrs["external_id"].present? && attrs["external_source"].present?
              "Cliente marcado como sincronizado. Encomendas pendentes vão ser enviadas para o ERP."
            else
              "Customer updated successfully."
            end
      redirect_to bo_customer_path(params[:org_slug], @customer, filter_params_hash), notice: msg
    else
      @customer_categories = current_organisation.customer_categories.ordered
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @customer.destroy
    redirect_to bo_customers_path(params[:org_slug], filter_params_hash), status: :see_other, notice: "Customer deleted successfully."
  end

  helper_method :filter_params_hash, :sort_link_params

  private

  def exportable_class
    Customer
  end

  def exportable_base_scope
    policy_scope(current_organisation.customers).includes(:customer_category)
  end

  def apply_export_filters(scope)
    apply_customer_filters(scope)
  end

  def filter_params_hash
    { query: params[:query], status: params[:status], category: params[:category],
      sort: params[:sort], direction: params[:direction], page: params[:page] }.compact_blank
  end

  def sort_link_params(column)
    direction = (@sort_column == column && @sort_direction == "asc") ? "desc" : "asc"
    filter_params_hash.except(:page).merge(sort: column, direction: direction)
  end

  def customer_params
    raw = params.require(:customer).permit(
      :company_name, :contact_name, :email, :contact_phone, :active,
      :taxpayer_id, :email_notifications_enabled, :customer_category_id,
      :external_id,
      billing_address_with_archived_attributes: [:id, :street_name, :street_nr, :postal_code, :city, :country, :address_type, :active],
      shipping_addresses_with_archived_attributes: [:id, :street_name, :street_nr, :postal_code, :city, :country, :address_type, :_destroy, :active]
    )

    # external_id is the ERP id — never settable by reps; only admins/owners
    # can mark a customer as synced manually (or it's filled by ERP sync).
    raw = raw.except(:external_id) unless current_org_member&.role&.in?(%w[owner admin])

    return raw unless pure_sales_rep?

    # Pure reps can't set pricing tier (customer_category) or toggle active state.
    # On update: NIF + billing address are locked (immutable identity / anti-fraud).
    # Shipping addresses can have NEW entries appended, but existing ones can't
    # be edited or deleted — strip any sub-hash carrying an :id from the
    # nested-attributes payload so only fresh additions go through.
    restricted = raw.except(:customer_category_id, :active)
    if action_name == "update"
      restricted = restricted.except(:taxpayer_id, :billing_address_with_archived_attributes)

      ship_attrs = restricted[:shipping_addresses_with_archived_attributes]
      restricted[:shipping_addresses_with_archived_attributes] = strip_existing_address_attrs(ship_attrs) if ship_attrs.present?
    end
    restricted
  end

  # Filters a nested-attributes payload (array or hash form) down to entries
  # that are new records (no :id). Protects pure-rep updates from sneaking in
  # edits or destroys against existing shipping address rows.
  def strip_existing_address_attrs(attrs)
    case attrs
    when Array
      attrs.reject { |a| a[:id].present? || a["id"].present? }
    when ActionController::Parameters, Hash
      attrs.reject { |_, a| (a[:id].presence || a["id"].presence).present? }
    else
      attrs
    end
  end

  def load_customers
    @customers = apply_customer_filters(
      policy_scope(current_organisation.customers)
        .includes(:customer_category, :customer_users, customer_assignment: { org_member: :member })
    )

    @sort_column = %w[company_name contact_name email active].include?(params[:sort]) ? params[:sort] : "company_name"
    @sort_direction = %w[asc desc].include?(params[:direction]) ? params[:direction] : "asc"
    @customers = @customers.order(@sort_column => @sort_direction)
    @pagy, @customers = pagy(@customers)

    @last_customer_sync = current_organisation.erp_sync_logs.for_entity('customers').completed.recent.first if current_organisation.erp_configuration&.enabled?
  end

  def apply_customer_filters(scope)
    if params[:query].present?
      scope = scope.where(
        "unaccent(company_name) ILIKE unaccent(:q) OR unaccent(contact_name) ILIKE unaccent(:q) OR unaccent(email) ILIKE unaccent(:q) OR unaccent(external_id) ILIKE unaccent(:q)",
        q: "%#{params[:query]}%"
      )
    end

    case params[:status]
    when "pending_erp_sync"
      scope = scope.pending_erp_sync if erp_customer_sync_enabled?
    when "no_rep"
      scope = scope.left_joins(:customer_assignment).where(customer_assignments: { id: nil })
    when "active"
      # Has at least one active login that has accepted its invitation.
      scope = scope.where(active: true)
                   .joins(:customer_users)
                   .where(customer_users: { active: true })
                   .where.not(customer_users: { invitation_accepted_at: nil })
                   .distinct
    when "inactive"
      # Customer.active = false OR has logins but all are deactivated.
      scope = scope.where(<<~SQL.squish)
        customers.active = FALSE
        OR (
          customers.active = TRUE
          AND EXISTS (SELECT 1 FROM customer_users cu WHERE cu.customer_id = customers.id)
          AND NOT EXISTS (SELECT 1 FROM customer_users cu WHERE cu.customer_id = customers.id AND cu.active = TRUE)
        )
      SQL
    when "pending"
      # At least one login invited but none accepted yet.
      accepted_ids = Customer.joins(:customer_users)
                             .where.not(customer_users: { invitation_accepted_at: nil })
                             .select(:id)
      scope = scope.where(active: true)
                   .joins(:customer_users)
                   .where.not(customer_users: { invitation_sent_at: nil })
                   .where.not(id: accepted_ids)
                   .distinct
    when "not_invited"
      # No logins yet, or none have been invited.
      invited_ids = Customer.joins(:customer_users)
                            .where.not(customer_users: { invitation_sent_at: nil })
                            .select(:id)
      scope = scope.where(active: true).where.not(id: invited_ids)
    end

    scope = scope.where(customer_category_id: params[:category]) if params[:category].present?

    scope
  end

  def set_and_authorize_customer
    @customer = current_organisation.customers.find(params[:id])
    authorize @customer
  end
end
