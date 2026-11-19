class Storefront::OrderBundlesController < Storefront::BaseController
  before_action :require_customer!

  def create
    product = current_organisation.products.bundles.where(published: true).find(params[:product_id])
    authorize current_cart.order_items.build(product: product), :create?
    if params[:quick_add] == "1" && !product.quick_add_available?
      render json: { message: t("bundles.errors.unavailable") }, status: :unprocessable_entity
      return
    end
    BundleCartService.new(current_cart).add!(product, params[:quantity])
    if params[:quick_add] == "1"
      render json: { message: t("bundles.added"), cart_count: current_cart.line_item_count }
      return
    end
    redirect_to cart_path(org_slug: params[:org_slug]), notice: t("bundles.added")
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    if params[:quick_add] == "1"
      render json: { message: e.message }, status: :unprocessable_entity
    else
      redirect_to product_path(org_slug: params[:org_slug], id: product), alert: e.message
    end
  end

  def update
    group = current_cart.order_bundles.find(params[:id])
    authorize group.order_items.first, :update?
    BundleCartService.new(current_cart).update!(group, params[:quantity])
    redirect_to cart_path(org_slug: params[:org_slug]), notice: t("bundles.saved")
  rescue ArgumentError, ActiveRecord::RecordInvalid => e
    redirect_to cart_path(org_slug: params[:org_slug]), alert: e.message
  end

  def destroy
    group = current_cart.order_bundles.find(params[:id])
    authorize group.order_items.first, :destroy?
    current_cart.with_lock { group.destroy! }
    redirect_to cart_path(org_slug: params[:org_slug]), notice: t("bundles.removed")
  end
end
