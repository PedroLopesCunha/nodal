class Bo::CustomerProductDiscountsController < Bo::BaseController
  before_action :set_discount, only: [:edit, :update, :destroy, :toggle_active]
  before_action :load_form_collections, only: [:new, :create, :edit, :update]

  def index
    @discounts = policy_scope(current_organisation.customer_product_discounts).includes(:customer, :product)
  end

  def new
    @discount = CustomerProductDiscount.new
    authorize @discount
  end

  def create
    @discount = CustomerProductDiscount.new(customer_product_discount_params)
    @discount.organisation = current_organisation
    authorize @discount

    if @discount.save
      update_variant_overrides
      begin
        CustomerMailer.with(discount: @discount, organisation: current_organisation).notify_customer_about_discount.deliver_now
      rescue => e
        Rails.logger.error("Failed to send customer product discount email: #{e.message}")
      end
      redirect_to bo_pricing_path(params[:org_slug], tab: 'custom_pricing'),
                  notice: "Custom price created successfully."
    else
      load_variants_for_form
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_variants_for_form
  end

  def variant_overrides
    authorize CustomerProductDiscount.new(organisation: current_organisation), :new?
    @variants_grouped = {}

    if params[:product_id].present?
      product = current_organisation.products.find_by(id: params[:product_id])
      @variants_grouped = { product => product.product_variants.by_position.to_a } if product
    elsif params[:category_id].present?
      category = current_organisation.categories.find_by(id: params[:category_id])
      if category
        product_ids = CategoryProduct.where(category_id: category.subtree_ids).select(:product_id)
        current_organisation.products.where(id: product_ids).includes(:product_variants).order(:name).each do |product|
          variants = product.product_variants.by_position.to_a
          @variants_grouped[product] = variants if variants.any?
        end
      end
    end

    render partial: "bo/product_discounts/variant_overrides_frame", locals: { variants_grouped: @variants_grouped, currency_symbol: current_organisation.currency_symbol }, layout: false
  end

  def update
    if @discount.update(customer_product_discount_params)
      update_variant_overrides
      redirect_to bo_pricing_path(params[:org_slug], tab: 'custom_pricing'),
                  notice: "Custom price updated successfully."
    else
      load_variants_for_form
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @discount.destroy
    redirect_to bo_pricing_path(params[:org_slug], tab: 'custom_pricing'),
                notice: "Custom price deleted successfully."
  end

  def toggle_active
    @discount.update(active: !@discount.active)
    redirect_to bo_pricing_path(params[:org_slug], tab: 'custom_pricing'),
                notice: "Discount #{@discount.active? ? 'activated' : 'deactivated'}."
  end

  private

  def set_discount
    @discount = current_organisation.customer_product_discounts.find(params[:id])
    authorize @discount
  end

  def load_form_collections
    @customers = current_organisation.customers.order(:company_name)
    @products = current_organisation.products.order(:name)
    @categories_for_select = current_organisation.categories.kept.order(:name).map do |cat|
      [cat.full_path, cat.id]
    end
  end

  def customer_product_discount_params
    params.require(:customer_product_discount).permit(
      :customer_id, :product_id, :category_id, :discount_percentage, :discount_type,
      :valid_from, :valid_until, :stackable, :active
    )
  end

  def load_variants_for_form
    if @discount.product?
      @variants_grouped = { @discount.product => @discount.product.product_variants.by_position.to_a }
    elsif @discount.category?
      @variants_grouped = {}
      product_ids = CategoryProduct.where(category_id: @discount.category.subtree_ids).select(:product_id)
      current_organisation.products.where(id: product_ids).includes(:product_variants).order(:name).each do |product|
        variants = product.product_variants.by_position.to_a
        @variants_grouped[product] = variants if variants.any?
      end
    else
      @variants_grouped = {}
    end
  end

  def update_variant_overrides
    overrides = params[:variant_overrides]
    return unless overrides

    variant_ids = overrides.keys.map(&:to_i)
    variants = ProductVariant.joins(:product)
                             .where(products: { organisation_id: current_organisation.id })
                             .where(id: variant_ids)

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
