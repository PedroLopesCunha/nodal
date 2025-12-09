class Storefront::ProductsController < Storefront::BaseController
  def index
    @products = policy_scope(current_organisation.products).includes(:category, :product_discounts)
    @categories = current_organisation.categories

    if params[:category].present?
      @products = @products.where(category_id: params[:category])
    end

    if params[:query].present?
      query = "%#{params[:query]}%"
      @products = @products.where("name ILIKE ? OR description ILIKE ?", query, query)
    end

    # Build discount info for all products using DiscountCalculator
    @product_discounts = @products.each_with_object({}) do |product, hash|
      calculator = DiscountCalculator.new(product: product, customer: current_customer)
      hash[product.id] = calculator.discount_breakdown
    end
  end

  def show
    @product = current_organisation.products.find(params[:id])
    authorize @product
    @discount_calculator = DiscountCalculator.new(product: @product, customer: current_customer)
  end
end
