class Bo::OrdersController < Bo::BaseController

  def index
    @orders = policy_scope(Order)
  end

  def show
    @order = Order.find(params[:id])
    authorize @order
  end

end
