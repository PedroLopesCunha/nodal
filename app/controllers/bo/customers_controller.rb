class Bo::CustomersController < Bo::BaseController
  before_action :set_and_authorize_customer, only: [:show, :edit, :update, :destroy, :invite]

  def index
    @tab = params[:tab] || 'customers'
    @customer_categories = current_organisation.customer_categories.ordered

    # Always call policy_scope to satisfy Pundit's verify_policy_scoped
    load_customers
  end

  def show
  end

  def new
    @customer = Customer.new
    @customer_categories = current_organisation.customer_categories.ordered
    authorize @customer
  end

  def create
    @customer = Customer.new(customer_params)
    @customer.organisation = current_organisation
    authorize @customer
    if @customer.save
      redirect_to bo_customer_path(params[:org_slug], @customer), notice: "Customer created successfully."
    else
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
    if @customer.update(customer_params)
      @customer.reload
      redirect_to bo_customer_path(params[:org_slug], @customer, filter_params_hash), notice: "Customer updated successfully."
    else
      @customer_categories = current_organisation.customer_categories.ordered
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @customer.destroy
    redirect_to bo_customers_path(params[:org_slug], filter_params_hash), status: :see_other, notice: "Customer deleted successfully."
  end

  def invite
    @customer.invite!
    redirect_to bo_customer_path(params[:org_slug], @customer),
                notice: "Invitation sent to #{@customer.email}"
  end

  helper_method :filter_params_hash, :sort_link_params

  private

  def filter_params_hash
    { query: params[:query], status: params[:status], category: params[:category],
      sort: params[:sort], direction: params[:direction] }.compact_blank
  end

  def sort_link_params(column)
    direction = (@sort_column == column && @sort_direction == "asc") ? "desc" : "asc"
    filter_params_hash.merge(sort: column, direction: direction)
  end

  def customer_params
    params.require(:customer).permit(:company_name, :contact_name, :email, :contact_phone, :active, :password, :password_confirmation, :taxpayer_id, :email_notifications_enabled, :customer_category_id, billing_address_with_archived_attributes: [:id, :street_name, :street_nr, :postal_code, :city, :country, :address_type, :active], shipping_addresses_with_archived_attributes: [:id, :street_name, :street_nr, :postal_code, :city, :country, :address_type, :_destroy, :active])
  end

  def load_customers
    @customers = policy_scope(current_organisation.customers).includes(:customer_category)

    if params[:query].present?
      @customers = @customers.where(
        "company_name ILIKE :q OR contact_name ILIKE :q OR email ILIKE :q OR external_id ILIKE :q",
        q: "%#{params[:query]}%"
      )
    end

    case params[:status]
    when "active" then @customers = @customers.where(active: true)
    when "inactive" then @customers = @customers.where(active: false)
    end

    if params[:category].present?
      @customers = @customers.where(customer_category_id: params[:category])
    end

    @sort_column = %w[company_name contact_name email active].include?(params[:sort]) ? params[:sort] : "company_name"
    @sort_direction = %w[asc desc].include?(params[:direction]) ? params[:direction] : "asc"
    @customers = @customers.order(@sort_column => @sort_direction)
    @pagy, @customers = pagy(@customers)

    @last_customer_sync = current_organisation.erp_sync_logs.for_entity('customers').completed.recent.first if current_organisation.erp_configuration&.enabled?
  end

  def set_and_authorize_customer
    @customer = current_organisation.customers.find(params[:id])
    authorize @customer
  end
end
