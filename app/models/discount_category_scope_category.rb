class DiscountCategoryScopeCategory < ApplicationRecord
  belongs_to :discount_category_scope, inverse_of: :discount_category_scope_categories
  belongs_to :category
  validate :same_organisation

  def same_organisation
    if category && discount_category_scope && category.organisation_id != discount_category_scope.organisation_id
      errors.add(:category, "must belong to the scope organisation")
    end
  end

  validates :category_id, uniqueness: { scope: :discount_category_scope_id }, unless: -> { discount_category_scope&.new_record? }
end
