class CustomerUser < ApplicationRecord
  belongs_to :customer
  belongs_to :organisation
  has_many :orders, dependent: :nullify
end
