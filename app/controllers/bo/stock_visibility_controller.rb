class Bo::StockVisibilityController < Bo::BaseController
  before_action :ensure_stock_display_enabled

  COMPANY_PICKER_LIMIT = 50

  # The companies allowed to see stock quantities in the shop.
  def show
    authorize current_organisation, :manage_stock_visibility?, policy_class: SettingPolicy

    @permitted_customers = current_organisation.customers
                                               .where(sees_stock_quantities: true)
                                               .includes(:customer_category)
                                               .order(:company_name)
  end

  # The whole list is submitted, so removing is just leaving a company out. One
  # write decides the state of every company rather than a stream of individual
  # toggles that can half-apply.
  def update
    authorize current_organisation, :manage_stock_visibility?, policy_class: SettingPolicy

    permitted_ids = Array(params[:customer_ids]).reject(&:blank?).map(&:to_i)
    scope = current_organisation.customers

    ActiveRecord::Base.transaction do
      scope.where(id: permitted_ids).update_all(sees_stock_quantities: true)
      scope.where.not(id: permitted_ids).update_all(sees_stock_quantities: false)
    end

    redirect_to bo_stock_visibility_path(params[:org_slug]),
                notice: t("bo.stock_visibility.updated", count: permitted_ids.size)
  end

  # Feeds the modal. A category is a way to pick its companies in bulk — the
  # answer is always companies, never the category itself, so reclassifying a
  # customer later never grants access on its own.
  def company_picker
    authorize current_organisation, :manage_stock_visibility?, policy_class: SettingPolicy

    @categories = current_organisation.customer_categories.order(:name)
    @customers = picker_scope

    render partial: "company_picker", formats: [ :html ]
  end

  private

  def picker_scope
    scope = current_organisation.customers.includes(:customer_category).order(:company_name)

    if params[:customer_category_id].present?
      scope = scope.where(customer_category_id: params[:customer_category_id])
      # Picking a category means picking everyone in it, so the list is not cut
      # short — a partial selection would be a lie.
      return scope
    end

    if params[:query].present?
      scope = scope.where(
        "unaccent(company_name) ILIKE unaccent(:q) OR unaccent(taxpayer_id) ILIKE unaccent(:q)",
        q: "%#{params[:query]}%"
      )
    end

    scope.limit(COMPANY_PICKER_LIMIT)
  end

  def ensure_stock_display_enabled
    return if current_organisation&.shows_stock_quantities?

    redirect_to edit_bo_settings_path(params[:org_slug]),
                alert: t("bo.stock_visibility.not_enabled")
  end
end
