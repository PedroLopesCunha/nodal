class Bo::OrderDiscountCampaignsController < Bo::BaseController
  include EditsDiscountCategoryScopes
  before_action :set_campaign, only: %i[edit update destroy]

  def new
    @campaign = current_organisation.order_discount_campaigns.build(priority: (current_organisation.order_discount_campaigns.maximum(:priority) || 0) + 1)
    @campaign.configure_category_scopes(mode: "all")
    authorize @campaign
  end

  def create
    @campaign = current_organisation.order_discount_campaigns.build
    authorize @campaign
    if persist_scoped_discount(@campaign, campaign_params)
      redirect_to bo_pricing_path(params[:org_slug], tab: 'order_tiers'), notice: "Campanha criada. Adicione os escalões à campanha."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if persist_scoped_discount(@campaign, campaign_params)
      redirect_to bo_pricing_path(params[:org_slug], tab: 'order_tiers'), notice: "Campanha atualizada."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @campaign.destroy
    redirect_to bo_pricing_path(params[:org_slug], tab: 'order_tiers'), alert: @campaign.errors.full_messages.to_sentence.presence
  end

  private

  def set_campaign
    @campaign = current_organisation.order_discount_campaigns.find(params[:id])
    authorize @campaign
  end

  def campaign_params
    params.require(:order_discount_campaign).permit(:name, :priority)
  end
end
