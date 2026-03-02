class Bo::ProductDiscountsController < Bo::BaseController
  before_action :set_discount, only: [:edit, :update, :destroy, :toggle_active]
  before_action :load_form_collections, only: [:new, :create, :edit, :update]

  def new
    @discount = ProductDiscount.new
    authorize @discount
  end

  def create
    @discount = ProductDiscount.new(product_discount_params)
    @discount.organisation = current_organisation
    authorize @discount

    if @discount.save
      update_variant_overrides
      CustomerMailer.with(discount: @discount, organisation: current_organisation).notify_clients_about_discount.deliver_now
      redirect_to bo_pricing_path(params[:org_slug], tab: 'product_discounts'),
                  notice: "Product discount created successfully."
    else
      @variants = @discount.product_id.present? ? current_organisation.products.find_by(id: @discount.product_id)&.product_variants&.by_position || [] : []
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @variants = @discount.product.product_variants.by_position
  end

  def variant_overrides
    authorize ProductDiscount.new(organisation: current_organisation), :new?
    @variants = []
    if params[:product_id].present?
      product = current_organisation.products.find_by(id: params[:product_id])
      @variants = product.product_variants.by_position if product
    end
    render partial: "variant_overrides_frame", locals: { variants: @variants, currency_symbol: current_organisation.currency_symbol }, layout: false
  end

  def update
    if @discount.update(product_discount_params)
      update_variant_overrides
      redirect_to bo_pricing_path(params[:org_slug], tab: 'product_discounts'),
                  notice: "Product discount updated successfully."
    else
      @variants = @discount.product.product_variants.by_position
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @discount.destroy
    redirect_to bo_pricing_path(params[:org_slug], tab: 'product_discounts'),
                notice: "Product discount deleted successfully."
  end

  def toggle_active
    @discount.update(active: !@discount.active)
    redirect_to bo_pricing_path(params[:org_slug], tab: 'product_discounts'),
                notice: "Discount #{@discount.active? ? 'activated' : 'deactivated'}."
  end

  private

  def set_discount
    @discount = current_organisation.product_discounts.find(params[:id])
    authorize @discount
  end

  def load_form_collections
    @products = current_organisation.products.order(:name)
  end

  def product_discount_params
    params.require(:product_discount).permit(
      :product_id, :discount_type, :discount_value, :min_quantity,
      :valid_from, :valid_until, :stackable, :active
    )
  end

  def update_variant_overrides
    overrides = params[:variant_overrides]
    return unless overrides

    variants = @discount.product.product_variants.where(id: overrides.keys)
    variants.each do |variant|
      data = overrides[variant.id.to_s]
      variant.update(
        exclude_from_discounts: data[:exclude_from_discounts] == "1",
        custom_discount_type: data[:custom_discount_type].presence,
        custom_discount_value: data[:custom_discount_value].presence
      )
    end
  end
end
