class Organisation < ApplicationRecord
  validates :slug, uniqueness: true
end
