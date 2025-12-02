class Category < ApplicationRecord
  belongs_to :organisation

  validates :name, presence: :true
  validates :name, uniqueness: { case_sensitive: false; scope: :organisation,
    message: "Category #{:name} already exists"}

  before_save :ensure_writing

  prive

  def ensure_writing
    name.lowercase.capitalize
  end
end
