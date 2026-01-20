class Storefront::ProductsController < Storefront::BaseController
  def index
    @products = policy_scope(current_organisation.products).includes(:categories, :product_discounts)

    # Load categories tree for sidebar
    @categories = current_organisation.categories.kept.roots.by_position

    # Filter by category and all its descendants
    if params[:category].present?
      @current_category = current_organisation.categories.kept.find_by(id: params[:category])
      if @current_category
        category_ids = @current_category.subtree_ids
        matching_ids = @products.joins(:category_products)
                                .where(category_products: { category_id: category_ids })
                                .select("products.id").distinct
        @products = @products.where(id: matching_ids)
        @breadcrumbs = @current_category.ancestors.to_a << @current_category
      end
    end

    if params[:query].present?
      query = "%#{params[:query]}%"
      @products = @products.where("products.name ILIKE ? OR products.description ILIKE ?", query, query)
    end

    # Build discount info for all products using DiscountCalculator
    # for_display: true shows all available discounts (ignoring min_quantity) for display purposes
    @product_discounts = @products.each_with_object({}) do |product, hash|
      calculator = DiscountCalculator.new(product: product, customer: current_customer, for_display: true)
      hash[product.id] = calculator.discount_breakdown
    end
  end

  def show
    @product = current_organisation.products.find(params[:id])
    authorize @product

    # Build breadcrumbs from primary category
    @primary_category = @product.primary_category
    if @primary_category
      @breadcrumbs = @primary_category.ancestors.to_a << @primary_category
    end

    # for_display: true shows all available discounts (ignoring min_quantity) for display purposes
    @discount_calculator = DiscountCalculator.new(product: @product, customer: current_customer, for_display: true)
  end
end
