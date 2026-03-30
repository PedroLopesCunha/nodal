class HomepageBanner < ApplicationRecord
  belongs_to :organisation

  has_one_attached :image

  acts_as_list scope: :organisation_id

  validates :image, presence: true, on: :update

  scope :active, -> { where(active: true) }
  scope :by_position, -> { order(:position) }
end
