class OrderDiscountCampaign < ApplicationRecord
  include HasCategoryScopes

  belongs_to :organisation
  has_many :order_discounts, dependent: :restrict_with_error
  validates :name, presence: true
  validates :priority, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :organisation_id }
  before_validation :ensure_scopes

  private

  def ensure_scopes
    configure_category_scopes(mode: "all") if category_scopes.empty? && organisation
  end
end
