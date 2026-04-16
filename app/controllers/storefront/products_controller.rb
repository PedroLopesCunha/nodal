class Storefront::ProductsController < Storefront::BaseController
  def index
    base_products = policy_scope(current_organisation.products).includes(:categories, :product_discounts)
                      .where(published: true)
    # Hide unavailable products, unless any variant has a non-hide policy
    keep_visible_ids = current_organisation.product_variants
                                           .where.not(stock_policy: ['hide', 'inherit'])
                                           .select(:product_id)
    if current_organisation.hide_out_of_stock?
      # For inherit+hide org, also keep products with inherit variants that aren't hidden
      base_products = base_products.where(available: true)
                                   .or(base_products.where(id: keep_visible_ids))
    end

    # Load categories tree for sidebar (eager load full tree to avoid N+1)
    @all_kept_categories = current_organisation.categories.kept.by_position.to_a
    @categories = @all_kept_categories.select { |c| c.ancestry.nil? }

    # Precompute product counts and children lookup (2 queries instead of N+1)
    direct_counts = CategoryProduct
      .where(category_id: @all_kept_categories.map(&:id))
      .group(:category_id)
      .distinct
      .count(:product_id)
    # Sum descendant counts in memory using ancestry strings
    @category_counts = {}
    @all_kept_categories.each do |cat|
      descendant_ids = @all_kept_categories
        .select { |c| c.id == cat.id || c.ancestry.to_s.split('/').map(&:to_i).include?(cat.id) }
        .map(&:id)
      @category_counts[cat.id] = direct_counts.values_at(*descendant_ids).compact.sum
    end
    # Children lookup to avoid N+1 in tree rendering
    @category_children = @all_kept_categories.group_by(&:parent_id)

    # Parse single selected category (accepts id or slug)
    if params[:category].present?
      cat_param = params[:category]
      @current_category = if cat_param.to_s =~ /\A\d+\z/
        current_organisation.categories.kept.find_by(id: cat_param)
      else
        current_organisation.categories.kept.find_by(slug: cat_param)
      end
    end
    # Keep as array for backward compatibility with shared views
    @current_categories = @current_category ? [ @current_category ] : []

    # Build product IDs from selected category (includes subcategories)
    category_product_ids = []
    if @current_category
      all_category_ids = @current_category.subtree_ids
      category_product_ids = base_products.joins(:category_products)
                                          .where(category_products: { category_id: all_category_ids })
                                          .pluck(:id).uniq

      @breadcrumbs = @current_category.ancestors.to_a << @current_category
    end

    # Parse search queries (multiple terms with OR logic)
    @current_queries = Array(params[:queries]).map(&:strip).reject(&:blank?).uniq

    # Build product IDs from search queries (OR logic across all terms)
    search_product_ids = search_products(base_products, @current_queries)

    # Combine with AND logic: category AND search (intersection)
    if @current_category && @current_queries.any?
      combined_ids = (category_product_ids & search_product_ids)
      products = combined_ids.any? ? base_products.where(id: combined_ids) : base_products.none
    elsif @current_category
      products = category_product_ids.any? ? base_products.where(id: category_product_ids) : base_products.none
    elsif @current_queries.any?
      products = search_product_ids.any? ? base_products.where(id: search_product_ids) : base_products.none
    else
      products = base_products
    end

    # Parse attribute filters: params[:attrs] = { "cor" => ["vermelho", "azul"], "espessura" => ["10"] }
    @current_attrs = {}
    if params[:attrs].present? && params[:attrs].is_a?(ActionController::Parameters)
      params[:attrs].each do |attr_slug, value_slugs|
        slugs = Array(value_slugs).map(&:strip).reject(&:blank?)
        @current_attrs[attr_slug] = slugs if slugs.any?
      end
    end

    # Filter products by attribute values (AND across attributes, OR within each attribute)
    if @current_attrs.any?
      attr_filtered_ids = nil
      @current_attrs.each do |attr_slug, value_slugs|
        ids = products
          .joins(product_variants: :variant_attribute_values)
          .joins("INNER JOIN product_attribute_values pav ON pav.id = variant_attribute_values.product_attribute_value_id")
          .joins("INNER JOIN product_attributes pa ON pa.id = pav.product_attribute_id")
          .where(product_variants: { published: true })
          .where("pa.slug = ? AND pav.slug IN (?)", attr_slug, value_slugs)
          .distinct.pluck(:id)
        attr_filtered_ids = attr_filtered_ids ? (attr_filtered_ids & ids) : ids
      end
      products = products.where(id: attr_filtered_ids || [])
    end

    # Collect available attribute filters only when a category is selected
    # (showing attributes across all categories is confusing — values from unrelated categories mix together)
    @available_attributes = @current_category ? build_available_attributes(products, @current_attrs) : []

    # Sort
    @current_sort = params[:sort].presence || "name_asc"
    min_variant_price = "(SELECT MIN(pv.unit_price_cents) FROM product_variants pv WHERE pv.product_id = products.id AND pv.published = true)"
    sorted_products = case @current_sort
                      when "name_desc" then products.order(name: :desc)
                      when "price_asc" then products.order(Arel.sql("#{min_variant_price} ASC NULLS LAST, products.name ASC"))
                      when "price_desc" then products.order(Arel.sql("#{min_variant_price} DESC NULLS LAST, products.name ASC"))
                      when "newest" then products.order(created_at: :desc)
                      else products.order(name: :asc)
                      end

    # Paginate results
    @pagy, @products = pagy(sorted_products)

    # Build discount info for all products using DiscountCalculator
    # for_display: true shows all available discounts (ignoring min_quantity) for display purposes
    @product_discounts = @products.each_with_object({}) do |product, hash|
      calculator = DiscountCalculator.new(product: product, customer: current_customer, for_display: true)
      hash[product.id] = calculator.discount_breakdown
    end

    @active_filters = build_active_filters
  end

  def autocomplete
    skip_authorization
    query = params[:q].to_s.strip
    if query.length < 2
      render json: []
      return
    end

    base = policy_scope(current_organisation.products).where(published: true, available: true)
    like_query = "%#{query}%"

    # Find matching categories
    categories = current_organisation.categories.kept
                   .where("unaccent(categories.name) ILIKE unaccent(?)", like_query)
                   .order(:name)
                   .limit(4)

    if categories.empty?
      categories = current_organisation.categories.kept
                     .where("word_similarity(unaccent(?), unaccent(categories.name)) > ?", query, TRIGRAM_THRESHOLD)
                     .order(:name)
                     .limit(4)
    end

    # Find matching products (by name, SKU, variant SKU, or category name)
    by_fields = base.left_joins(:product_variants)
                    .where("unaccent(products.name) ILIKE unaccent(?) OR unaccent(products.sku) ILIKE unaccent(?) OR unaccent(product_variants.sku) ILIKE unaccent(?)", like_query, like_query, like_query)
    by_cat = base.joins(:categories)
                 .where("unaccent(categories.name) ILIKE unaccent(?)", like_query)
    products = by_fields.or(base.where(id: by_cat.select(:id)))
                   .select("products.id, products.name, products.slug, products.sku")
                   .distinct
                   .order(:name)
                   .limit(5)

    if products.empty?
      products = base.where("word_similarity(unaccent(?), unaccent(products.name)) > ?", query, TRIGRAM_THRESHOLD)
                     .select(:id, :name, :slug, :sku)
                     .order(:name)
                     .limit(5)
    end

    results = {
      categories: categories.map { |c| { name: c.name, path: c.full_path, url: products_path(org_slug: params[:org_slug], category: c.slug) } },
      products: products.map { |p| { name: p.name, sku: p.sku, url: product_path(p, org_slug: params[:org_slug]) } },
      search_url: products_path(org_slug: params[:org_slug], "queries[]": query)
    }

    render json: results
  end

  def show
    @product = current_organisation.products.find(params[:id])
    authorize @product

    unless @product.published?
      redirect_to products_path(org_slug: current_organisation.slug), alert: I18n.t('storefront.products.not_available')
      return
    end

    if !@product.available?
      # Product has no available variants — check if any variant's policy would still show it
      has_visible = @product.product_variants.published.where(is_default: false).any? { |v|
        v.effective_stock_policy != 'hide'
      }
      unless has_visible
        redirect_to products_path(org_slug: current_organisation.slug), alert: I18n.t('storefront.products.not_available')
        return
      end
    end

    # Build breadcrumbs from primary category
    @primary_category = @product.primary_category
    if @primary_category
      @breadcrumbs = @primary_category.ancestors.to_a << @primary_category
    end

    # Load variants data for variable products
    if @product.has_variants?
      # Only show published, non-default variants; filter out hidden-when-unavailable
      all_variants = @product.product_variants.published.where(is_default: false)
                            .by_position.includes(:attribute_values)
      @variants = all_variants.select { |v|
        v.available? || v.effective_stock_policy != 'hide'
      }
      # Only show attribute values that lead to at least one available variant
      variant_value_ids = @variants.flat_map { |v| v.attribute_values.map(&:id) }.to_set
      @attributes_with_values = @product.available_values_by_attribute.transform_values { |values|
        values.select { |v| variant_value_ids.include?(v.id) }
      }
      @default_variant = @product.default_variant

      # Compute per-variant discount data for JS
      @variant_discounts = @variants.each_with_object({}) do |v, hash|
        calc = DiscountCalculator.new(product: @product, customer: current_customer, for_display: true, variant: v)
        bd = calc.discount_breakdown
        hash[v.id] = {
          has_discount: bd[:has_discount],
          final_price_cents: bd[:final_price].cents,
          discount_percentage: bd[:has_discount] && bd[:effective_discount][:percentage].to_f.finite? ? (bd[:effective_discount][:percentage] * 100).round(0) : 0
        }
      end
    else
      @default_variant = @product.default_variant
      # Load attribute values for simple products (for display)
      if @default_variant&.attribute_values&.any?
        @simple_attribute_values = @default_variant.attribute_values
          .joins(:product_attribute)
          .includes(:product_attribute)
          .order('product_attributes.position')
      end
    end

    # for_display: true shows all available discounts (ignoring min_quantity) for display purposes
    @discount_calculator = DiscountCalculator.new(
      product: @product,
      customer: current_customer,
      for_display: true,
      variant: @default_variant
    )

    # Fetch related products
    if @product.show_related_products?
      fetcher = RelatedProductsFetcher.new(product: @product, limit: 4)
      @related_products = fetcher.fetch
      @related_product_discounts = build_discounts_for(@related_products)
    end
  end

  private

  TRIGRAM_THRESHOLD = 0.5

  def search_products(base_products, queries)
    return [] if queries.blank?

    product_ids = []
    queries.each do |term|
      ids = exact_search(base_products, term) + fuzzy_search(base_products, term)
      product_ids += ids
    end
    product_ids.uniq
  end

  def exact_search(base_products, term)
    query = "%#{term}%"
    ids_by_category = base_products.joins(:categories)
                                   .where("unaccent(categories.name) ILIKE unaccent(?)", query)
                                   .pluck(:id)
    ids_by_product = base_products.left_joins(:product_variants).where(
      "unaccent(products.name) ILIKE unaccent(?) OR unaccent(products.description) ILIKE unaccent(?) OR unaccent(products.sku) ILIKE unaccent(?) OR unaccent(product_variants.sku) ILIKE unaccent(?)",
      query, query, query, query
    ).pluck(:id)
    (ids_by_product + ids_by_category).uniq
  end

  def fuzzy_search(base_products, term)
    ids_by_product = base_products.where(
      "word_similarity(unaccent(?), unaccent(products.name)) > ?", term, TRIGRAM_THRESHOLD
    ).pluck(:id)
    ids_by_category = base_products.joins(:categories).where(
      "word_similarity(unaccent(?), unaccent(categories.name)) > ?", term, TRIGRAM_THRESHOLD
    ).pluck(:id)
    (ids_by_product + ids_by_category).uniq
  end

  def build_active_filters
    filters = []

    @current_queries.each do |term|
      remaining_queries = @current_queries - [ term ]
      remove_params = request.query_parameters.except("queries", "page")
      remove_params["queries"] = remaining_queries if remaining_queries.any?

      filters << {
        type: :query,
        label: term,
        remove_params: remove_params
      }
    end

    @current_attrs.each do |attr_slug, value_slugs|
      attr = @available_attributes&.find { |a| a[:slug] == attr_slug }
      attr_name = attr ? attr[:name] : attr_slug

      value_slugs.each do |value_slug|
        value_label = attr&.dig(:values)&.find { |v| v[:slug] == value_slug }&.dig(:label) || value_slug
        remaining = value_slugs - [value_slug]
        remove_params = request.query_parameters.except("page").deep_dup
        if remaining.any?
          remove_params["attrs"][attr_slug] = remaining
        else
          remove_params["attrs"]&.delete(attr_slug)
          remove_params.delete("attrs") if remove_params["attrs"]&.empty?
        end

        filters << {
          type: :attribute,
          label: "#{attr_name}: #{value_label}",
          remove_params: remove_params
        }
      end
    end

    filters
  end

  def build_available_attributes(products, current_attrs)
    product_ids = products.pluck(:id)
    return [] if product_ids.empty?

    # Query attribute values present in available variants of these products
    rows = ProductAttributeValue
      .joins(:product_attribute, variant_attribute_values: { product_variant: :product })
      .where(products: { id: product_ids })
      .where(product_variants: { published: true })
      .group("product_attributes.id", "product_attributes.name", "product_attributes.slug", "product_attributes.position",
             "product_attribute_values.id", "product_attribute_values.value", "product_attribute_values.slug",
             "product_attribute_values.color_hex", "product_attribute_values.position")
      .order(Arel.sql("product_attributes.position"))
      .pluck(
        Arel.sql("product_attributes.id"), Arel.sql("product_attributes.name"), Arel.sql("product_attributes.slug"),
        Arel.sql("product_attribute_values.id"), Arel.sql("product_attribute_values.value"), Arel.sql("product_attribute_values.slug"),
        Arel.sql("product_attribute_values.color_hex"),
        Arel.sql("COUNT(DISTINCT products.id)")
      )

    # Group into structured data
    attrs_hash = {}
    rows.each do |attr_id, attr_name, attr_slug, _val_id, val_label, val_slug, color_hex, count|
      attrs_hash[attr_id] ||= { name: attr_name, slug: attr_slug, values: [] }
      attrs_hash[attr_id][:values] << {
        label: val_label,
        slug: val_slug,
        color_hex: color_hex,
        count: count,
        selected: current_attrs[attr_slug]&.include?(val_slug) || false
      }
    end

    # Sort values: numeric-first (by numeric value), then alphabetical
    attrs_hash.each_value do |attr|
      attr[:values].sort_by! do |v|
        label = v[:label].to_s
        num = label[/\A[\d.]+/]
        if num
          [0, num.to_f]
        else
          [1, label.downcase]
        end
      end
    end

    attrs_hash.values
  end

  def build_discounts_for(products)
    products.each_with_object({}) do |product, hash|
      calculator = DiscountCalculator.new(product: product, customer: current_customer, for_display: true)
      hash[product.id] = calculator.discount_breakdown
    end
  end
end
