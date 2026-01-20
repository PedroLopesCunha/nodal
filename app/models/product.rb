class Product < ApplicationRecord
  belongs_to :organisation
  belongs_to :category, optional: true  # Legacy direct association
  has_many :order_items, dependent: :restrict_with_error
  has_many :orders, through: :order_items
  has_many :customer_product_discounts, dependent: :destroy
  has_many :product_discounts, dependent: :destroy

  # Many-to-many categories relationship
  has_many :category_products, dependent: :destroy
  has_many :categories, through: :category_products

  has_one_attached :photo

  validates :slug, uniqueness: true
  validates :name, presence: true
  validates :description, length: { maximum: 150 }, allow_blank: true
  monetize :unit_price, as: :price

  def active_discount_for(customer)
    return nil unless customer
    customer_product_discounts.active.find_by(customer: customer)
  end

  def discounted_price_for(discount)
    return price unless discount
    price - (price * discount.discount_percentage)
  end

  # Returns the primary category (first by position) or falls back to legacy category
  def primary_category
    categories.joins(:category_products)
              .order('category_products.position')
              .first || category
  end
end

