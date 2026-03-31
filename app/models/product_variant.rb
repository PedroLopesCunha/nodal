class ProductVariant < ApplicationRecord
  include ErpSyncable
  include HasExportableColumns

  belongs_to :organisation
  belongs_to :product
  has_many :variant_attribute_values, dependent: :destroy
  has_many :attribute_values, through: :variant_attribute_values, source: :product_attribute_value
  has_many :order_items, dependent: :restrict_with_error

  has_one_attached :photo

  acts_as_list scope: :product

  monetize :unit_price_cents, as: :price, allow_nil: true

  validates :name, presence: true
  validates :sku, uniqueness: { scope: :organisation_id, allow_blank: true }
  validates :custom_discount_type, inclusion: { in: %w[percentage fixed] }, allow_blank: true
  validates :custom_discount_value, presence: true, if: -> { custom_discount_type.present? }
  validates :custom_discount_type, presence: true, if: -> { custom_discount_value.present? }
  validates :custom_discount_value, numericality: { greater_than: 0 }, allow_nil: true

  before_validation :normalize_custom_discount_fields
  before_validation :set_organisation_from_product
  before_validation :set_currency_from_organisation
  before_validation :inherit_product_price, on: :create

  scope :by_position, -> { order(:position) }
  scope :available, -> { where(available: true) }
  scope :default, -> { where(is_default: true) }

  def self.exportable_columns
    [
      { key: :product_name, label: I18n.t("bo.export.columns.variant.product_name"), default: true,
        value: ->(r) { r.product&.name } },
      { key: :variant_name, label: I18n.t("bo.export.columns.variant.variant_name"), default: true,
        value: ->(r) { r.name } },
      { key: :options, label: I18n.t("bo.export.columns.variant.options"), default: true,
        value: ->(r) { r.option_values_string.presence } },
      { key: :sku, label: I18n.t("bo.export.columns.variant.sku"), default: true,
        value: ->(r) { r.sku } },
      { key: :unit_price, label: I18n.t("bo.export.columns.variant.unit_price"), default: true,
        value: ->(r) { r.price&.format } },
      { key: :available, label: I18n.t("bo.export.columns.variant.available"), default: true,
        value: ->(r) { r.available? ? I18n.t("bo.common.yes") : I18n.t("bo.common.no") } },
      { key: :stock_quantity, label: I18n.t("bo.export.columns.variant.stock_quantity"), default: true,
        value: ->(r) { r.track_stock? ? r.stock_quantity : I18n.t("bo.export.columns.variant.unlimited") } },
      { key: :track_stock, label: I18n.t("bo.export.columns.variant.track_stock"), default: false,
        value: ->(r) { r.track_stock? ? I18n.t("bo.common.yes") : I18n.t("bo.common.no") } },
      { key: :is_default, label: I18n.t("bo.export.columns.variant.is_default"), default: false,
        value: ->(r) { r.is_default? ? I18n.t("bo.common.yes") : I18n.t("bo.common.no") } },
      { key: :categories, label: I18n.t("bo.export.columns.variant.categories"), default: false,
        value: ->(r) { r.product&.categories&.map(&:name)&.join(", ") } },
      { key: :product_type, label: I18n.t("bo.export.columns.variant.product_type"), default: false,
        value: ->(r) { r.product&.has_variants? ? I18n.t("bo.products.index.table.variable") : I18n.t("bo.products.index.table.simple") } }
    ]
  end

  def in_stock?
    return true unless track_stock?
    stock_quantity.to_i > 0
  end

  def purchasable?
    available? && in_stock? && !product.price_on_request?
  end

  def option_values_string
    attribute_values.joins(:product_attribute).order('product_attributes.position').map(&:value).join(' / ')
  end

  def display_name
    if is_default? && attribute_values.empty?
      product.name
    else
      "#{product.name} - #{option_values_string}"
    end
  end

  def has_custom_discount?
    custom_discount_type.present? && custom_discount_value.present?
  end

  def effective_photo
    return photo if photo.attached?
    return product.photo if product.photo_attached?
    nil
  end

  private

  def normalize_custom_discount_fields
    self.custom_discount_type = nil if custom_discount_type.blank?
    self.custom_discount_value = nil if custom_discount_value.blank?
  end

  def set_organisation_from_product
    self.organisation ||= product&.organisation
  end

  def set_currency_from_organisation
    self.unit_price_currency ||= organisation&.currency || 'EUR'
  end

  def inherit_product_price
    self.unit_price_cents ||= product&.unit_price
  end
end
