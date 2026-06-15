class Storefront::OrderItemsController < Storefront::BaseController
  before_action :require_customer!

  def create
    @product = current_organisation.products.where(published: true).find(params[:product_id])

    if @product.price_on_request?
      redirect_to product_path(org_slug: params[:org_slug], id: @product, category: params[:category], queries: params[:queries], page: params[:page]), alert: t('storefront.products.show.price_on_request_not_purchasable')
      return
    end

    @order = current_cart

    # Find or default to the product's default variant
    @variant = if params[:variant_id].present?
      @product.product_variants.find(params[:variant_id])
    else
      @product.default_variant
    end

    # Find existing order item by product + variant combination
    @order_item = @order.order_items.find_by(product: @product, product_variant: @variant)

    if @order_item
      @order_item.quantity += order_item_params[:quantity].to_i
    else
      # OrderItem callback set_discount_from_product will use DiscountCalculator
      # to apply the effective discount from all sources (ProductDiscount,
      # CustomerDiscount, CustomerProductDiscount)
      @order_item = @order.order_items.build(
        order_item_params.merge(product: @product, product_variant: @variant)
      )
    end

    authorize @order_item

    filter_params = { category: params[:category], queries: params[:queries], page: params[:page] }

    if @order_item.save
      redirect_to product_path(org_slug: params[:org_slug], id: @product, **filter_params), notice: t('storefront.cart.item_added')
    else
      redirect_to product_path(org_slug: params[:org_slug], id: @product.id, **filter_params),
                    alert: @order_item.errors.full_messages.join(", ")
    end
  end

  def update
    @order_item = current_cart.order_items.find(params[:id])
    authorize @order_item

    @order_item.assign_attributes(order_item_params)
    # :customer_change context enforces the minimum-quantity validation for a
    # customer-initiated edit (system re-pricing saves without a context).
    if @order_item.save(context: :customer_change)
      redirect_to cart_path(org_slug: params[:org_slug]), notice: "Cart updated."
    else
      redirect_to cart_path(org_slug: params[:org_slug]),
                  alert: @order_item.errors.full_messages.join(", ")
    end
  end

  def destroy
    @order_item = current_cart.order_items.find(params[:id])
    authorize @order_item
    @order_item.destroy
    redirect_to cart_path(org_slug: params[:org_slug]), notice: "Item removed."
  end

  # Bulk add multiple variants of one product to the cart in a single
  # submission. Best-effort: each row saves independently, the response
  # surfaces both successes and per-row failures so the customer isn't
  # blocked by one bad line.
  def bulk_add
    @product = current_organisation.products.where(published: true).find(params[:product_id])
    if @product.price_on_request?
      redirect_to product_path(org_slug: params[:org_slug], id: @product),
                  alert: t('storefront.products.show.price_on_request_not_purchasable')
      return
    end

    @order = current_cart
    authorize @order.order_items.build(product: @product), :create?
    bulk_items = params[:bulk_items].respond_to?(:each_pair) ? params[:bulk_items] : {}

    added = []
    failed = []

    bulk_items.each_pair do |variant_id, raw_qty|
      qty = raw_qty.to_i
      next if qty <= 0

      variant = @product.product_variants.find_by(id: variant_id)
      label = variant&.option_values_string.presence || variant&.name || variant_id.to_s

      unless variant
        failed << "#{label} (#{t('storefront.cart.bulk_add.variant_not_found')})"
        next
      end

      item = @order.order_items.find_by(product: @product, product_variant: variant)
      if item
        item.quantity += qty
      else
        item = @order.order_items.build(product: @product, product_variant: variant, quantity: qty)
      end

      if item.save
        added << label
      else
        failed << "#{label} (#{item.errors.full_messages.join(', ')})"
      end
    end

    if added.empty? && failed.empty?
      redirect_to product_path(org_slug: params[:org_slug], id: @product),
                  alert: t('storefront.cart.bulk_add.nothing_selected')
    elsif failed.any?
      flash[:alert] = t('storefront.cart.bulk_add.partial_failure', items: failed.to_sentence)
      redirect_to product_path(org_slug: params[:org_slug], id: @product),
                  notice: (added.any? ? t('storefront.cart.bulk_add.added', count: added.size) : nil)
    else
      redirect_to product_path(org_slug: params[:org_slug], id: @product),
                  notice: t('storefront.cart.bulk_add.added', count: added.size)
    end
  end

  private

  def order_item_params
    params.require(:order_item).permit(:quantity)
  end
end
