class Customer < ApplicationRecord
  include ErpSyncable
  include HasExportableColumns

  # Auth lives on CustomerUser, not on Customer. Customer is the empresa.
  # Auth-related columns (encrypted_password, reset_password_*, invitation_*,
  # remember_created_at, sign_in tracking) still exist on this table but are
  # orphan after the split — they get dropped in a follow-up migration so
  # rollback of this PR stays trivial.

  belongs_to :organisation
  belongs_to :customer_category, optional: true
  has_many :customer_users, dependent: :destroy
  has_many :orders, dependent: :destroy
  has_one :billing_address, -> { billing.active }, class_name: "Address", as: :addressable, dependent: :destroy
  has_many :shipping_addresses, -> { shipping.active }, class_name: "Address", as: :addressable, dependent: :destroy
  has_one :billing_address_with_archived, -> { billing }, class_name: "Address", as: :addressable, dependent: :destroy
  has_many :shipping_addresses_with_archived, -> { shipping }, class_name: "Address", as: :addressable, dependent: :destroy
  has_many :shopping_lists, dependent: :destroy
  has_many :customer_product_discounts, dependent: :destroy
  has_many :customer_discounts, dependent: :destroy
  has_many :promo_code_customers, dependent: :destroy
  has_many :promo_codes, through: :promo_code_customers
  has_many :promo_code_redemptions, dependent: :destroy
  has_many :email_logs, dependent: :nullify

  validates :company_name, presence: true
  validates :contact_name, presence: true
  validates :active, inclusion: { in: [true, false] }
  validates :locale, inclusion: { in: I18n.available_locales.map(&:to_s) }, allow_nil: true

  # Customers eligible to receive transactional/marketing emails: active,
  # accepted their invitation, and have notifications enabled. Auth emails
  # (reset password, invitation itself) bypass this — see EmailDeliveryGuard.
  scope :mailable, -> {
    where(active: true, email_notifications_enabled: true).where.not(invitation_accepted_at: nil)
  }

  def mailable?
    active? && email_notifications_enabled? && invitation_accepted_at.present?
  end

  def self.exportable_columns
    [
      { key: :company_name, label: I18n.t("bo.export.columns.customer.company_name"), default: true,
        value: ->(r) { r.company_name } },
      { key: :contact_name, label: I18n.t("bo.export.columns.customer.contact_name"), default: true,
        value: ->(r) { r.contact_name } },
      { key: :email, label: I18n.t("bo.export.columns.customer.email"), default: true,
        value: ->(r) { r.email } },
      { key: :contact_phone, label: I18n.t("bo.export.columns.customer.contact_phone"), default: true,
        value: ->(r) { r.contact_phone } },
      { key: :category, label: I18n.t("bo.export.columns.customer.category"), default: true,
        value: ->(r) { r.customer_category&.name } },
      { key: :taxpayer_id, label: I18n.t("bo.export.columns.customer.taxpayer_id"), default: false,
        value: ->(r) { r.taxpayer_id } },
      { key: :active, label: I18n.t("bo.export.columns.customer.active"), default: true,
        value: ->(r) { r.active? ? I18n.t("bo.common.yes") : I18n.t("bo.common.no") } },
      { key: :invitation_status, label: I18n.t("bo.export.columns.customer.invitation_status"), default: false,
        value: ->(r) { I18n.t("bo.common.statuses.#{r.invitation_status}") } },
      { key: :last_sign_in_at, label: I18n.t("bo.export.columns.customer.last_sign_in_at"), default: false,
        value: ->(r) { r.last_sign_in_at&.strftime("%Y-%m-%d %H:%M") } },
      { key: :created_at, label: I18n.t("bo.export.columns.customer.created_at"), default: false,
        value: ->(r) { I18n.l(r.created_at, format: :short) } }
    ]
  end

  # Email column is now an orphan ERP-mirror field (the login email lives
  # on CustomerUser). Format validated only when present.
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP, allow_blank: true },
                    if: :will_save_change_to_email?

  # Addresses validation (PEDRO)
  #accepts_nested_attributes_for :billing_address, update_only: true
  #accepts_nested_attributes_for :shipping_addresses
  #new below
  accepts_nested_attributes_for :billing_address_with_archived, update_only: true, reject_if: :address_blank?
  accepts_nested_attributes_for :shipping_addresses_with_archived, reject_if: :address_blank?


  def current_cart(organisation)
    orders.draft.find_or_create_by!(organisation: organisation)
  end

  def active_discounts_for_products(product_ids)
    # Direct customer discounts take precedence
    direct = customer_product_discounts
      .active
      .where(product_id: product_ids)
      .index_by(&:product_id)

    # Fill in category-based discounts for products not covered by direct
    if customer_category_id.present?
      missing_ids = product_ids - direct.keys
      if missing_ids.any?
        category_based = CustomerProductDiscount
          .where(customer_category_id: customer_category_id)
          .active
          .where(product_id: missing_ids)
          .index_by(&:product_id)
        direct.merge!(category_based)
      end
    end

    direct
  end

  def active_customer_discount
    # Direct customer discount takes precedence
    direct = customer_discounts.active.first
    return direct if direct

    # Fall back to category-based
    if customer_category_id.present?
      CustomerDiscount.where(customer_category_id: customer_category_id).active.first
    end
  end

  def has_active_global_discount?
    active_customer_discount.present?
  end

  def invitation_status
    if !active?
      :inactive
    elsif invitation_accepted_at.present?
      :active
    elsif invitation_sent_at.present?
      :pending
    else
      :not_invited
    end
  end

  private

  def address_blank?(attributes)
    attributes.except('id', 'address_type', 'active', '_destroy').values.all?(&:blank?)
  end
end
