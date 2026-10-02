class DiscountVariantPage
  LIMIT = 50
  attr_reader :page, :query, :grouped

  def initialize(products, page: 1, query: nil)
    @page = [page.to_i, 1].max
    @query = query.to_s.strip.first(100)
    variants = ProductVariant.joins(:product).where(product_id: products.select(:id))
    if @query.present?
      term = "%#{ActiveRecord::Base.sanitize_sql_like(@query)}%"
      variants = variants.where('products.name ILIKE :term OR products.sku ILIKE :term OR product_variants.name ILIKE :term OR product_variants.sku ILIKE :term', term: term)
    end
    rows = variants.includes(:product).order('products.name', 'products.id', :position, :id)
      .offset((@page - 1) * LIMIT).limit(LIMIT + 1).to_a
    @has_next = rows.size > LIMIT
    @grouped = rows.first(LIMIT).group_by(&:product)
  end

  def next_page? = @has_next
end
