module HasCategoryScopes
  extend ActiveSupport::Concern

  included do
    has_many :category_scopes, class_name: "DiscountCategoryScope", dependent: :destroy, autosave: true
    validates_associated :category_scopes
  end

  def qualification_scope
    category_scopes.find { |scope| scope.role == "qualification" }
  end

  def discount_scope
    category_scopes.find { |scope| scope.role == "discount" }
  end

  # The initial admin uses one configuration for both roles. Domain callers
  # can configure each role independently through the owned scope records.
  def configure_category_scopes(mode:, category_ids: [])
    ids = Array(category_ids).reject(&:blank?).map(&:to_i).uniq
    categories = organisation.categories.where(id: ids).to_a
    raise ActiveRecord::RecordNotFound, "Invalid category selection" unless categories.map(&:id).sort == ids.sort
    %w[qualification discount].each do |role|
      scope = category_scopes.find { |existing| existing.role == role } || category_scopes.build(role: role)
      scope.organisation = organisation
      scope.mode = mode
      scope.categories = categories
    end
  end
end
