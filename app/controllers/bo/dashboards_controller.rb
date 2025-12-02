class Bo::DashboardsController < Bo::BaseController
  def index
    @customers = policy_scope(current_organisation.customers)
  end
end
