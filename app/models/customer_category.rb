class CustomerCategory < ApplicationRecord
  belongs_to :organisation
  has_many :customers, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :organisation_id }

  scope :ordered, -> { order(:name) }
end
