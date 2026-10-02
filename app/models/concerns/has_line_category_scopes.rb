module HasLineCategoryScopes
  extend ActiveSupport::Concern
  include HasCategoryScopes

  included do
    before_validation :sync_legacy_category_scope
    after_save { @explicit_category_scopes = false }
  end

  def scoped_target?
    qualification_scope.present? && discount_scope.present?
  end

  def matches_discount_product?(product)
    (!product_id || product_id == product.id) && discount_scope&.matches_product?(product)
  end

  def category?
    product_id.blank? && (category_id.present? || scoped_target?)
  end

  def target_name
    return product&.name if product?
    discount_scope&.description || category&.full_path
  end

  def display_name
    name.presence || target_name
  end

  def category_scope_signature
    discount_scope&.signature || ["include", [category_id]]
  end

  private

  def sync_legacy_category_scope
    return unless organisation
    return if product_id.blank? && category_id.blank? && !@explicit_category_scopes && category_scopes.empty?
    # Old forms/API clients still edit category_id. The legacy column remains
    # an adapter; explicit scope configuration is authoritative otherwise.
    if category_id_changed? || product_id_changed? || category_scopes.empty?
      return if @explicit_category_scopes
      configure_category_scopes(mode: category_id ? "include" : "all", category_ids: category_id ? [category_id] : [])
    end
  end
end
