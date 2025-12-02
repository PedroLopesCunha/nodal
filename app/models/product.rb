class Product < ApplicationRecord
  belongs_to :organisation
  belongs_to :category
end
