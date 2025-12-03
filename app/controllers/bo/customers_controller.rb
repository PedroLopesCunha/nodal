class Bo::CustomersController < Bo::BaseController

  def index
    @customers=policy_scope(Customer)
    @customers=Customer.all
  end

  def show
    @customer = Customer.find(params[:id])
    authorize @customer
  end

end
