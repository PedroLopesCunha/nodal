module EditsDiscountCategoryScopes
  extend ActiveSupport::Concern

  private

  def persist_scoped_discount(record, attributes)
    saved = false
    record.class.transaction do
      record.assign_attributes(attributes)
      if params[:scope_config].present?
        config = params.require(:scope_config).permit(:mode, category_ids: [])
        if params[:target_type] == "product"
          record.category_id = nil if record.respond_to?(:category_id=)
          record.configure_category_scopes(mode: "all")
        else
          record.product_id = nil if record.respond_to?(:product_id=)
          record.category_id = nil if record.respond_to?(:category_id=)
          record.configure_category_scopes(mode: config[:mode], category_ids: config[:category_ids])
        end
      end
      saved = record.save
      raise ActiveRecord::Rollback unless saved
    end
    saved
  rescue ActiveRecord::RecordNotFound
    record.errors.add(:base, "Seleção de categorias inválida para esta organização")
    false
  end

  def variant_products_for_scope
    if params[:product_id].present?
      current_organisation.products.where(id: params[:product_id])
    else
      config = params.permit(:scope_mode, :category_id, category_ids: [])
      ids = Array(config[:category_ids]).presence || [config[:category_id]].compact
      categories = current_organisation.categories.where(id: ids.reject(&:blank?)).to_a
      raise ActiveRecord::RecordNotFound unless categories.size == ids.reject(&:blank?).map(&:to_i).uniq.size
      scope = DiscountCategoryScope.new(organisation: current_organisation, mode: config[:scope_mode].presence || "include")
      scope.categories = categories
      scope.product_relation
    end
  end

  def scoped_variants_for(record)
    products = if record.product?
      current_organisation.products.where(id: record.product_id)
    elsif record.discount_scope
      record.discount_scope.product_relation
    else
      current_organisation.products.none
    end
    load_variant_page(products)
  end

  def load_variant_page(products)
    @variant_page = DiscountVariantPage.new(products, page: params[:variant_page] || 1, query: params[:variant_query])
    @variant_page.grouped
  end
end
