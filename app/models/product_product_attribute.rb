class ProductProductAttribute < ApplicationRecord
  belongs_to :product
  belongs_to :product_attribute

  acts_as_list scope: :product

  validates :product_attribute_id, uniqueness: { scope: :product_id }
  validate :same_organisation

  scope :by_position, -> { order(:position) }

  delegate :name, :slug, to: :product_attribute, prefix: :attribute

  private

  def same_organisation
    return if product.nil? || product_attribute.nil?

    unless product.organisation_id == product_attribute.organisation_id
      errors.add(:product_attribute, "must belong to the same organisation as the product")
    end
  end
end
