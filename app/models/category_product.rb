class CategoryProduct < ApplicationRecord
  belongs_to :category
  belongs_to :product

  acts_as_list scope: :category_id

  validates :category_id, uniqueness: { scope: :product_id, message: "product already assigned to this category" }
  validate :same_organisation

  private

  def same_organisation
    return unless category.present? && product.present?

    if category.organisation_id != product.organisation_id
      errors.add(:base, "Category and product must belong to the same organisation")
    end
  end
end
