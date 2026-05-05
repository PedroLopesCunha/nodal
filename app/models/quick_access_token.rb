class QuickAccessToken < ApplicationRecord
  belongs_to :customer_user
  belongs_to :created_by_member, class_name: "Member", optional: true

  validates :token, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }
  scope :revoked, -> { where.not(revoked_at: nil) }

  before_validation :generate_token, on: :create
  before_validation :default_expires_at, on: :create

  def self.generate_for(customer_user, created_by:)
    transaction do
      customer_user.quick_access_tokens.active.update_all(revoked_at: Time.current)
      customer_user.quick_access_tokens.create!(created_by_member: created_by)
    end
  end

  def active?
    revoked_at.nil? && expires_at > Time.current
  end

  def expired?
    expires_at <= Time.current
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def mark_used!
    update_column(:last_used_at, Time.current)
  end

  private

  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(32)
  end

  def default_expires_at
    return if expires_at.present?

    days = customer_user&.organisation&.quick_access_token_ttl_days || 90
    self.expires_at = days.days.from_now
  end
end
