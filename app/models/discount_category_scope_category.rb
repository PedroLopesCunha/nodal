class DiscountCategoryScopeCategory < ApplicationRecord
  belongs_to :discount_category_scope
  belongs_to :category
  validates :category_id, uniqueness: { scope: :discount_category_scope_id }, unless: -> { discount_category_scope&.new_record? }
end
