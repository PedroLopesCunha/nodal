class Bo::OrdersController < Bo::BaseController
  include Exportable

  before_action :set_order, only: [:show, :edit, :update, :destroy, :apply_discount, :remove_discount, :download_pdf]

  def index
    @orders = apply_order_filters(policy_scope(current_organisation.orders.placed).includes(:customer, :order_items))

    sort_direction = %w[asc desc].include?(params[:sort_dir]) ? params[:sort_dir] : "desc"
    @orders = @orders.order(Arel.sql("COALESCE(orders.placed_at, orders.created_at) #{sort_direction}"))
    @pagy, @orders = pagy(@orders)

    @customers = current_organisation.customers.order(:company_name)
  end

  def show
    @order.mark_as_reviewed!
  end

  def edit
    @products = Product.where(organisation: @current_organisation)
  end

  def new
    @order = Order.new
    @customers = Customer.where(organisation: @current_organisation)
    @products = Product.where(organisation: @current_organisation)
    authorize @order
  end

  def create
    @order = Order.new(order_params)
    @order.organisation = @current_organisation
    @order.placed_at = Time.current
    authorize @order

    if @order.save
      redirect_to bo_order_path(org_slug: @current_organisation.slug, id: @order.id), notice: "Order created successfully."
    else
      @customers = Customer.where(organisation: @current_organisation)
      @products = Product.where(organisation: @current_organisation)
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @order.update(order_params)
      redirect_to bo_order_path(org_slug: @current_organisation.slug, id: @order.id, **filter_params_hash), notice: "Order updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @order.destroy
    redirect_to bo_orders_path(org_slug: @current_organisation.slug, **filter_params_hash), notice: "Order deleted successfully."
  end

  def apply_discount
    if @order.update(order_discount_params.merge(applied_by: current_member))
      redirect_to bo_order_path(org_slug: @current_organisation.slug, id: @order.id),
                  notice: "Discount applied successfully."
    else
      redirect_to bo_order_path(org_slug: @current_organisation.slug, id: @order.id),
                  alert: "Failed to apply discount: #{@order.errors.full_messages.join(', ')}"
    end
  end

  def remove_discount
    @order.update(discount_type: nil, discount_value: nil, discount_reason: nil, applied_by: nil)
    redirect_to bo_order_path(org_slug: @current_organisation.slug, id: @order.id),
                notice: "Discount removed."
  end

  def download_pdf
    html = render_to_string(template: "shared/orders/pdf", layout: false)
    pdf = Grover.new(html).to_pdf

    send_data pdf,
      filename: "#{@order.order_number}.pdf",
      type: "application/pdf",
      disposition: "attachment"
  end

  def export_items
    authorize Order, :export?

    columns = OrderItem.exportable_columns_for(params[:columns])
    format = params[:format_type] || "csv"
    extension = format == "xlsx" ? "xlsx" : "csv"

    order_ids = apply_order_filters(policy_scope(current_organisation.orders.placed)).select(:id)
    records = OrderItem.where(order_id: order_ids).includes(:order, :product, :product_variant, order: :customer)

    result = ExportService.new(records: records, columns: columns, format: format).call
    filename = "order_items_#{Date.today.iso8601}.#{extension}"
    send_data result[:data], filename: filename, type: result[:content_type], disposition: "attachment"
  end

  helper_method :filter_params_hash

  private

  def exportable_class
    Order
  end

  def exportable_base_scope
    policy_scope(current_organisation.orders.placed).includes(:customer, :order_items)
  end

  def apply_export_filters(scope)
    apply_order_filters(scope)
  end

  def filter_params_hash
    { search: params[:search], status: params[:status],
      payment_status: params[:payment_status], customer_id: params[:customer_id],
      date_from: params[:date_from], date_to: params[:date_to],
      sort_dir: params[:sort_dir] }.compact_blank
  end

  def apply_order_filters(scope)
    if params[:search].present?
      search_term = "%#{params[:search]}%"
      scope = scope.joins(:customer).where(
        "unaccent(orders.order_number) ILIKE unaccent(:search) OR unaccent(customers.company_name) ILIKE unaccent(:search) OR unaccent(customers.contact_name) ILIKE unaccent(:search)",
        search: search_term
      )
    end

    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(payment_status: params[:payment_status]) if params[:payment_status].present?
    scope = scope.where(customer_id: params[:customer_id]) if params[:customer_id].present?

    if params[:date_from].present?
      scope = scope.where("COALESCE(orders.placed_at, orders.created_at) >= ?", params[:date_from].to_date.beginning_of_day)
    end

    if params[:date_to].present?
      scope = scope.where("COALESCE(orders.placed_at, orders.created_at) <= ?", params[:date_to].to_date.end_of_day)
    end

    scope
  end

  def set_order
    @order = Order.find(params[:id])
    authorize @order
  end

  def order_params
    params.require(:order).permit(
      :customer_id, :status, :payment_status, :receive_on, :notes,
      order_items_attributes: [:id, :product_id, :quantity, :price, :discount_percentage, :_destroy]
    )
  end

  def order_discount_params
    params.require(:order).permit(:discount_type, :discount_value, :discount_reason)
  end
end
