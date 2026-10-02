class Bo::OrderDiscountsController < Bo::BaseController
  before_action :set_discount, only: [:edit, :update, :destroy, :toggle_active]

  def new
    @discount = OrderDiscount.new
    @discount.order_discount_campaign = current_organisation.order_discount_campaigns.find(params[:campaign_id]) if params[:campaign_id].present?
    authorize @discount
  end

  def create
    @discount = OrderDiscount.new(order_discount_params)
    @discount.organisation = current_organisation
    resolve_campaign
    authorize @discount

    if @discount.save
      notification = DiscountEmailNotification.create!(
        notifiable: @discount,
        organisation: current_organisation,
        status: 'pending',
        recipient_count: DiscountEmailNotification.recipient_count_for(@discount, current_organisation)
      )
      redirect_to bo_pricing_path(params[:org_slug], tab: 'order_tiers', notification_id: notification.id),
                  notice: "Order discount created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    @discount.assign_attributes(order_discount_params)
    resolve_campaign
    if @discount.save
      redirect_to bo_pricing_path(params[:org_slug], tab: 'order_tiers'),
                  notice: "Order discount updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @discount.destroy
      redirect_to bo_pricing_path(params[:org_slug], tab: 'order_tiers'),
                  notice: "Order discount deleted successfully."
    else
      redirect_to bo_pricing_path(params[:org_slug], tab: 'order_tiers'),
                  alert: @discount.errors.full_messages.to_sentence
    end
  rescue ActiveRecord::InvalidForeignKey
    # The database remains the final safeguard if an order references this
    # tier between the model's existence check and the DELETE.
    raise unless @discount.orders.exists?

    redirect_to bo_pricing_path(params[:org_slug], tab: 'order_tiers'),
                alert: OrderDiscount::USED_TIER_DELETION_MESSAGE
  end

  def toggle_active
    @discount.update(active: !@discount.active)
    redirect_to bo_pricing_path(params[:org_slug], tab: 'order_tiers'),
                notice: "Discount #{@discount.active? ? 'activated' : 'deactivated'}."
  end

  private

  def set_discount
    @discount = current_organisation.order_discounts.find(params[:id])
    authorize @discount
  end

  def resolve_campaign
    if @discount.order_discount_campaign_id
      @discount.order_discount_campaign = current_organisation.order_discount_campaigns.find(@discount.order_discount_campaign_id)
    end
  end

  def order_discount_params
    params.require(:order_discount).permit(
      :order_discount_campaign_id, :discount_type, :discount_value, :min_order_amount,
      :valid_from, :valid_until, :stackable, :active
    )
  end
end
