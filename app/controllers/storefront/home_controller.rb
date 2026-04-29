class Storefront::HomeController < Storefront::BaseController
  skip_after_action :verify_authorized

  def show
    @banners = current_organisation.homepage_banners.active.by_position.includes(image_attachment: :blob)
    @featured_categories = current_organisation.homepage_featured_categories
                             .order(:position)
                             .includes(category: { photo_attachment: :blob })
                             .map(&:category)
    @featured_products = load_featured_products
    @special_price_products = load_special_price_products
    @frequent_products = load_frequent_products
    @new_products = load_new_products

    unless browsing_as_member?
      @last_order = current_customer.orders.placed
                      .includes(:order_items)
                      .order(placed_at: :desc)
                      .first

      @shopping_lists = current_customer.shopping_lists
                          .ordered
                          .includes(:shopping_list_items)
                          .limit(3)

      @tier_discount = current_customer.active_customer_discount
      @special_prices_count = current_customer.customer_product_discounts.active.count
      @total_orders_count = current_customer.orders.placed.count
      @active_promo_codes = current_organisation.promo_codes.active
        .left_joins(:promo_code_customers)
        .where(eligibility: 'all_customers')
        .or(current_organisation.promo_codes.active
          .left_joins(:promo_code_customers)
          .where(eligibility: 'specific_customers', promo_code_customers: { customer_id: current_customer.id }))
        .distinct
    end

    @products_count = current_organisation.products.where(published: true).count

    # Build discount info for all displayed products
    all_products = @featured_products + @special_price_products + @frequent_products + @new_products
    @product_discounts = all_products.uniq.each_with_object({}) do |product, hash|
      calculator = DiscountCalculator.new(product: product, customer: current_customer, for_display: true)
      hash[product.id] = calculator.discount_breakdown
    end
  end

  private

  def load_featured_products
    featured_product_ids = current_organisation.homepage_featured_products
                             .order(:position)
                             .pluck(:product_id)
    return [] if featured_product_ids.empty?

    products = current_organisation.products
                 .where(id: featured_product_ids, published: true)
                 .includes(:categories, :product_discounts)

    if current_organisation.hide_out_of_stock?
      keep_visible_ids = current_organisation.product_variants
                           .where.not(stock_policy: ['hide', 'inherit'])
                           .select(:product_id)
      products = products.where(available: true)
                   .or(products.where(id: keep_visible_ids))
    end

    # Preserve position order
    products_by_id = products.index_by(&:id)
    featured_product_ids.filter_map { |id| products_by_id[id] }
  end

  # Curated "Special Prices" section. Same shape as featured products, but
  # filtered to only products with an actually-applicable discount for the
  # current viewer:
  #   - logged-in customer: products where the customer has any active discount
  #   - admin / anonymous: products with a public ProductDiscount (item or category)
  def load_special_price_products
    curated_ids = current_organisation.homepage_special_price_products
                                       .order(:position)
                                       .pluck(:product_id)
    return [] if curated_ids.empty?

    products = current_organisation.products
                 .where(id: curated_ids, published: true)
                 .includes(:categories, :product_discounts)

    if current_organisation.hide_out_of_stock?
      keep_visible_ids = current_organisation.product_variants
                           .where.not(stock_policy: ['hide', 'inherit'])
                           .select(:product_id)
      products = products.where(available: true)
                   .or(products.where(id: keep_visible_ids))
    end

    products = products.to_a

    products = if browsing_as_member? || current_customer.nil?
      products.select { |p| has_public_discount?(p) }
    else
      products.select do |p|
        DiscountCalculator.new(product: p, customer: current_customer, for_display: true)
                          .discount_breakdown[:has_discount]
      end
    end

    by_id = products.index_by(&:id)
    curated_ids.filter_map { |id| by_id[id] }
  end

  def has_public_discount?(product)
    return true if product.product_discounts.active.exists?

    category_path_ids = product.categories.flat_map(&:path_ids).uniq
    return false if category_path_ids.empty?

    ProductDiscount.active.for_category
                   .where(organisation: product.organisation, category_id: category_path_ids)
                   .exists?
  end

  def load_frequent_products
    return [] if browsing_as_member?

    # Top 8 most-ordered products by this customer
    frequent_product_ids = OrderItem
      .joins(:order)
      .where(orders: { customer_id: current_customer.id, organisation_id: current_organisation.id })
      .where.not(orders: { placed_at: nil })
      .group(:product_id)
      .order(Arel.sql("COUNT(*) DESC"))
      .limit(12)
      .pluck(:product_id)

    return [] if frequent_product_ids.empty?

    products = current_organisation.products
                 .where(id: frequent_product_ids, published: true)
                 .includes(:categories, :product_discounts)

    # Preserve frequency order
    products.sort_by { |p| frequent_product_ids.index(p.id) }
  end

  def load_new_products
    cutoff = if !browsing_as_member? && current_customer.orders.placed.exists?
               current_customer.orders.placed.order(placed_at: :desc).pick(:placed_at)
             else
               30.days.ago
             end

    base = current_organisation.products
             .where("products.created_at > ?", cutoff)
             .where(published: true)
             .includes(:categories, :product_discounts)
             .order(created_at: :desc)
             .limit(12)

    if current_organisation.hide_out_of_stock?
      keep_visible_ids = current_organisation.product_variants
                           .where.not(stock_policy: ['hide', 'inherit'])
                           .select(:product_id)
      base = base.where(available: true)
                 .or(base.where(id: keep_visible_ids))
    end

    base.to_a
  end
end
