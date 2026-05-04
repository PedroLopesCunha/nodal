class CustomerUser < ApplicationRecord
  # Devise modules — auth lives on CustomerUser (the login), not on
  # Customer (the empresa). One Customer can have many CustomerUsers.
  devise :database_authenticatable,
         :recoverable, :rememberable, :invitable, :trackable,
         authentication_keys: [:email, :organisation_id]

  def devise_mailer
    CustomerUserMailer
  end

  belongs_to :customer
  belongs_to :organisation
  has_many :orders, dependent: :nullify

  # Each login has its own cart, isolated from other CustomerUsers of the
  # same Customer (empresa). Returns the draft order for this user in the
  # given organisation, creating one if it doesn't exist.
  def current_cart(organisation)
    orders.draft.find_or_create_by!(
      organisation: organisation,
      customer_id: customer_id
    )
  end

  validates :active, inclusion: { in: [true, false] }
  validates :locale, inclusion: { in: I18n.available_locales.map(&:to_s) }, allow_nil: true

  # Mailable: active CustomerUsers whose Customer (empresa) is also active,
  # who have accepted their invitation, and have notifications enabled.
  scope :mailable, -> {
    where(active: true, email_notifications_enabled: true)
      .where.not(invitation_accepted_at: nil)
      .joins(:customer).where(customers: { active: true })
  }

  def mailable?
    active? &&
      email_notifications_enabled? &&
      invitation_accepted_at.present? &&
      customer&.active?
  end
end
