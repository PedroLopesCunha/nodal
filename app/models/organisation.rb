class Organisation < ApplicationRecord
  has_many :categories, dependent: :destroy

  validates :slug, uniqueness: true
end
