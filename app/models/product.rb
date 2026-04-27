class Product < ApplicationRecord
  include Slugable
  include HasExportableColumns

  # Storefront sort options exposed in the products listing dropdown.
  # Reused by Organisation and Category to validate their default_product_sort.
  SORT_OPTIONS = %w[name_asc name_desc price_asc price_desc newest].freeze

  slugify :name, secondary: :sku

  belongs_to :organisation
  belongs_to :category, optional: true  # Legacy direct association
  has_many :order_items, dependent: :restrict_with_error
  has_many :orders, through: :order_items
  has_many :customer_product_discounts, dependent: :destroy
  has_many :product_discounts, dependent: :destroy

  # Many-to-many categories relationship
  has_many :category_products, dependent: :destroy
  has_many :categories, through: :category_products

  # Related products
  has_many :related_product_associations, class_name: "RelatedProduct", dependent: :destroy
  has_many :manual_related_products, through: :related_product_associations, source: :related_product
  has_many :inverse_related_product_associations, class_name: "RelatedProduct",
           foreign_key: :related_product_id, dependent: :destroy

  # Variants and attributes
  has_many :product_variants, dependent: :destroy
  has_many :product_product_attributes, dependent: :destroy
  has_many :product_attributes, through: :product_product_attributes
  has_many :product_available_values, dependent: :destroy
  has_many :available_attribute_values, through: :product_available_values, source: :product_attribute_value

  has_many_attached :photos
  has_rich_text :rich_description

  # Returns the cover photo if set, otherwise falls back to first photo
  def photo
    if cover_photo_blob_id.present?
      photos.find { |p| p.blob_id == cover_photo_blob_id } || photos.first
    else
      photos.first
    end
  end

  # Check if any photos are attached
  def photo_attached?
    photos.attached? && photos.any?
  end

  # Returns a display photo, falling back to variant photos for variable products
  def display_photo
    return photo if photo_attached?
    return nil unless has_variants?

    product_variants.where(is_default: false).each do |v|
      return v.photo if v.photo.attached?
    end
    nil
  end

  # Aggregates product photos + variant photos (for variable products)
  def all_photos
    result = photos.to_a
    if has_variants?
      product_variants.where(is_default: false).each do |v|
        result << v.photo if v.photo.attached?
      end
    end
    result
  end

  validates :slug, uniqueness: true
  validates :name, presence: true
  monetize :unit_price, as: :price, allow_nil: true

  before_save :sync_description_columns
  after_create :create_default_variant
  after_update :sync_default_variant, if: :should_sync_default_variant?
  after_update :clear_default_variant_for_variable, if: :became_variable?

  scope :simple, -> { where(has_variants: false) }
  scope :variable, -> { where(has_variants: true) }

  def self.exportable_columns
    [
      { key: :name, label: I18n.t("bo.export.columns.product.name"), default: true,
        value: ->(r) { r.name } },
      { key: :sku, label: I18n.t("bo.export.columns.product.sku"), default: true,
        value: ->(r) { r.sku } },
      { key: :description, label: I18n.t("bo.export.columns.product.description"), default: false,
        value: ->(r) { r.rich_description.body&.to_plain_text.presence || r.description } },
      { key: :unit_price, label: I18n.t("bo.export.columns.product.unit_price"), default: true,
        value: ->(r) { r.price&.format } },
      { key: :price_on_request, label: I18n.t("bo.export.columns.product.price_on_request"), default: false,
        value: ->(r) { r.price_on_request? ? I18n.t("bo.common.yes") : I18n.t("bo.common.no") } },
      { key: :published, label: I18n.t("bo.export.columns.product.published"), default: true,
        value: ->(r) { r.published? ? I18n.t("bo.common.yes") : I18n.t("bo.common.no") } },
      { key: :product_type, label: I18n.t("bo.export.columns.product.product_type"), default: true,
        value: ->(r) { r.has_variants? ? I18n.t("bo.products.index.table.variable") : I18n.t("bo.products.index.table.simple") } },
      { key: :categories, label: I18n.t("bo.export.columns.product.categories"), default: true,
        value: ->(r) { r.categories.map(&:name).join(", ") } },
      { key: :min_quantity, label: I18n.t("bo.export.columns.product.min_quantity"), default: false,
        value: ->(r) { r.min_quantity } },
      { key: :unit_description, label: I18n.t("bo.export.columns.product.unit_description"), default: false,
        value: ->(r) { r.unit_description } },
      { key: :created_at, label: I18n.t("bo.export.columns.product.created_at"), default: false,
        value: ->(r) { I18n.l(r.created_at, format: :short) } }
    ]
  end


  def active_discount_for(customer)
    return nil unless customer
    # Direct customer match takes precedence
    direct = customer_product_discounts.active.find_by(customer: customer)
    return direct if direct

    # Fall back to customer category match
    if customer.customer_category_id.present?
      customer_product_discounts.active.find_by(customer_category_id: customer.customer_category_id)
    end
  end

  def show_related_products?
    organisation.show_related_products? && !hide_related_products?
  end

  def discounted_price_for(discount)
    return price unless discount
    price - (price * discount.discount_percentage)
  end

  # Returns the primary category (first by position) or falls back to legacy category
  def primary_category
    categories.joins(:category_products)
              .order('category_products.position')
              .first || category
  end

  # Variant-related methods

  def default_variant
    product_variants.default.first || product_variants.first
  end

  def simple?
    !has_variants?
  end

  def variable?
    has_variants?
  end

  def purchasable?
    return false if price_on_request?
    variants = product_variants.published
    variants = variants.where(is_default: false) if has_variants? && product_variants.where(is_default: false).exists?
    variants.any?(&:purchasable?)
  end

  def price_range
    variants = product_variants.published
    # Exclude default base variant from range calculation for variable products
    variants = variants.where(is_default: false) if has_variants? && product_variants.where(is_default: false).exists?
    prices = variants.pluck(:unit_price_cents).compact
    return nil if prices.empty?

    min_price = Money.new(prices.min, organisation.currency)
    max_price = Money.new(prices.max, organisation.currency)

    { min: min_price, max: max_price, range: min_price != max_price }
  end

  def display_price
    range = price_range
    return price unless range

    if range[:range]
      "#{range[:min].format} - #{range[:max].format}"
    else
      range[:min].format
    end
  end

  def available_values_by_attribute
    product_attributes.by_position.each_with_object({}) do |attribute, hash|
      hash[attribute] = available_attribute_values
        .joins(:product_attribute)
        .where(product_attributes: { id: attribute.id })
        .includes(:product_attribute)
        .naturally_sorted
    end
  end

  def find_variant_by_attribute_values(attribute_value_ids)
    return default_variant if attribute_value_ids.blank?

    product_variants.find do |variant|
      variant.attribute_values.pluck(:id).sort == attribute_value_ids.map(&:to_i).sort
    end
  end

  private

  # Mirrors content between rich_description (Trix-edited) and the legacy
  # description column. When the form edits rich, description follows.
  # When imports/ERP sync set description directly, rich gets backfilled.
  # The body_changed? check distinguishes form path from import path so
  # clearing the rich editor doesn't get reverted from a stale description.
  def sync_description_columns
    if rich_description.body_changed?
      self.description = rich_description.body&.to_plain_text&.strip.presence
    elsif description_changed? && description.present?
      self.rich_description = description
    end
  end

  def create_default_variant
    return if product_variants.exists?

    if has_variants?
      product_variants.create!(
        name: name,
        unit_price_currency: organisation.currency,
        published: published,
        is_default: true,
        track_stock: false,
        position: 1
      )
    else
      product_variants.create!(
        name: name,
        sku: sku,
        unit_price_cents: unit_price,
        unit_price_currency: organisation.currency,
        published: published,
        is_default: true,
        position: 1
      )
    end
  end

  def should_sync_default_variant?
    !has_variants? && (saved_change_to_name? || saved_change_to_unit_price? || saved_change_to_sku? || saved_change_to_published?)
  end

  def sync_default_variant
    variant = default_variant
    return unless variant&.is_default?

    variant.update(
      name: name,
      sku: sku,
      unit_price_cents: unit_price,
      published: published
    )
  end

  def became_variable?
    saved_change_to_has_variants? && has_variants?
  end

  def clear_default_variant_for_variable
    variant = default_variant
    return unless variant&.is_default?

    variant.update_columns(
      sku: nil,
      unit_price_cents: nil,
      stock_quantity: 0,
      track_stock: false,
      external_id: nil,
      external_source: nil
    )
    update_columns(unit_price: nil)
  end
end
