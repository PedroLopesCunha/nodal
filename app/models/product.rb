class Product < ApplicationRecord
  belongs_to :organisation
  belongs_to :category
  has_many :order_items, dependent: :restrict_with_error
  has_many :orders, through: :order_items

  has_one_attached :photo

  validates :slug, uniqueness: true
  validates :name, presence: true
  validates :description, length: { minimum: 5, maximum: 150 }

  CURRENCY_SYMBOL = "€"

  def formatted_price
    return "-" unless unit_price.present?
    price = "#{CURRENCY_SYMBOL}#{'%.2f' % (unit_price / 100.0)}"
    unit_description.present? ? "#{price}/#{unit_description}" : price
  end

  def price_in_cents
    (unit_price || 0) / 100.0
  end

  def formatted_base_price
    "#{CURRENCY_SYMBOL}#{'%.2f' % price_in_cents}"
  end
end
