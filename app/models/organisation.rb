class Organisation < ApplicationRecord
  has_many :categories, dependent: :destroy
  has_many :products, dependent: :destroy

  validates :slug, uniqueness: true
end
