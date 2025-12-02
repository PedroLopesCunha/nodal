class Organisation < ApplicationRecord
  has_many: :categories, dependet: :destroy

  validates :slug, uniqueness: true
end
