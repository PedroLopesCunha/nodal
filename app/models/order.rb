class Order < ApplicationRecord
  include ErpSyncable
  include HasExportableColumns

  STATUSES = %w[in_process processed completed].freeze
  PAYMENT_STATUSES = %w[pending paid failed refunded].freeze
  DELIVERY_METHODS = %w[pickup delivery].freeze
  DISCOUNT_TYPES = %w[percentage fixed].freeze
  PUSH_STATUSES = %w[pending syncing synced failed].freeze
  MAX_PUSH_ATTEMPTS = 5

  monetize :tax_amount_cents, allow_nil: true
  monetize :shipping_amount_cents, allow_nil: true
  monetize :promo_code_discount_amount_cents, allow_nil: true

  # Virtual attribute used by the checkout form: when true, the customer
  # asked to ship to the billing address. Resolved in finalize_checkout!.
  attr_accessor :same_as_billing

  # Virtual attribute set by the checkout form's extra confirmation checkbox,
  # used by validate_checkout_stock! when checkout_stock_policy is "warn".
  attr_accessor :confirmed_stock_warnings

  belongs_to :customer
  belongs_to :customer_user, optional: true
  belongs_to :organisation
  belongs_to :shipping_address, class_name: "Address", optional: true
  belongs_to :billing_address, class_name: "Address", optional: true
  belongs_to :applied_by, class_name: "Member", optional: true
  belongs_to :placed_by, polymorphic: true, optional: true
  belongs_to :sales_rep, class_name: "OrgMember", optional: true
  belongs_to :order_discount, optional: true
  belongs_to :promo_code, optional: true
  has_many :order_items, dependent: :destroy
  has_many :products, through: :order_items
  has_one :promo_code_redemption, dependent: :destroy

  accepts_nested_attributes_for :order_items, allow_destroy: true, reject_if: :all_blank

  validates :order_number, presence: true, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :payment_status, inclusion: { in: PAYMENT_STATUSES }
  validates :delivery_method, inclusion: { in: DELIVERY_METHODS }, allow_nil: true
  validates :discount_type, inclusion: { in: DISCOUNT_TYPES }, allow_nil: true
  validates :push_status, inclusion: { in: PUSH_STATUSES }
  validates :discount_value, numericality: { greater_than: 0 }, allow_nil: true
  validate :discount_value_valid_for_type

  before_validation :generate_order_number, on: :create
  before_validation :update_tax, on: :update

  after_commit :enqueue_erp_push, if: :should_enqueue_erp_push?

  # Scopes for cart functionality
  scope :draft, -> { where(placed_at: nil) }
  scope :placed, -> { where.not(placed_at: nil) }
  scope :unreviewed, -> { placed.where(viewed_at: nil) }

  PUSH_RETRY_COOLDOWN = 10.minutes

  scope :push_pending, -> { where(push_status: "pending") }
  scope :push_synced, -> { where(push_status: "synced") }
  scope :push_failed, -> { where(push_status: "failed") }
  scope :pushable, -> {
    placed
      .where(push_status: %w[pending failed])
      .where("push_attempts < ?", MAX_PUSH_ATTEMPTS)
      .where("last_pushed_at IS NULL OR last_pushed_at < ?", PUSH_RETRY_COOLDOWN.ago)
  }

  def self.exportable_columns
    [
      { key: :order_number, label: I18n.t("bo.export.columns.order.order_number"), default: true,
        value: ->(r) { r.order_number } },
      { key: :customer_company, label: I18n.t("bo.export.columns.order.customer_company"), default: true,
        value: ->(r) { r.customer&.company_name } },
      { key: :customer_contact, label: I18n.t("bo.export.columns.order.customer_contact"), default: true,
        value: ->(r) { r.customer&.contact_name } },
      { key: :customer_email, label: I18n.t("bo.export.columns.order.customer_email"), default: false,
        value: ->(r) { r.customer&.email } },
      { key: :placed_by_user_name, label: I18n.t("bo.export.columns.order.placed_by_user_name"), default: false,
        value: ->(r) { r.customer_user&.contact_name } },
      { key: :placed_by_user_email, label: I18n.t("bo.export.columns.order.placed_by_user_email"), default: false,
        value: ->(r) { r.customer_user&.email } },
      { key: :status, label: I18n.t("bo.export.columns.order.status"), default: true,
        value: ->(r) { r.status&.titleize } },
      { key: :payment_status, label: I18n.t("bo.export.columns.order.payment_status"), default: true,
        value: ->(r) { r.payment_status&.titleize } },
      { key: :placed_at, label: I18n.t("bo.export.columns.order.placed_at"), default: true,
        value: ->(r) { r.placed_at&.strftime("%Y-%m-%d %H:%M") } },
      { key: :receive_on, label: I18n.t("bo.export.columns.order.receive_on"), default: false,
        value: ->(r) { r.receive_on&.strftime("%Y-%m-%d") } },
      { key: :delivery_method, label: I18n.t("bo.export.columns.order.delivery_method"), default: false,
        value: ->(r) { r.delivery_method&.titleize } },
      { key: :item_count, label: I18n.t("bo.export.columns.order.item_count"), default: true,
        value: ->(r) { r.order_items.sum(:quantity) } },
      { key: :total_amount, label: I18n.t("bo.export.columns.order.total_amount"), default: true,
        value: ->(r) { r.total_amount.format } },
      { key: :grand_total, label: I18n.t("bo.export.columns.order.grand_total"), default: true,
        value: ->(r) { r.grand_total.format } },
      { key: :notes, label: I18n.t("bo.export.columns.order.notes"), default: false,
        value: ->(r) { r.notes } }
    ]
  end

  def draft?
    placed_at.nil?
  end

  def placed?
    placed_at.present?
  end

  def mark_as_reviewed!
    update_column(:viewed_at, Time.current) if viewed_at.nil?
  end

  def item_count
    order_items.sum(:quantity)
  end

  def line_item_count
    order_items.size
  end

  def place!
    update!(placed_at: Time.current)
  end

  def push_synced?
    push_status == "synced"
  end

  def push_failed?
    push_status == "failed"
  end

  def push_pending?
    push_status == "pending"
  end

  def push_exhausted?
    push_attempts >= MAX_PUSH_ATTEMPTS
  end

  # Re-evaluates every line item against current data — re-pricing it and
  # reacting to stock changes per the organisation's cart policies — and
  # persists what moved. Returns a struct describing every change so callers
  # (cart/checkout) can surface it. No-op once the order is placed.
  #
  # Stock reactions:
  #   cart_stock_policy 'remove'    → drop items that went unpurchasable
  #   cart_qty_overflow_policy 'cap' → reduce qty to the available stock
  #   otherwise the issue is recorded for the view to warn about.
  def refresh_cart!
    changes = blank_cart_changes
    return changes if placed?

    order_items.to_a.each do |item|
      status = item.stock_status

      if status.in?(%i[out_of_stock variant_unpublished]) && organisation.cart_stock_policy == "remove"
        changes[:removed] << cart_item_label(item)
        item.destroy!
        next
      end

      item_changes = item.refresh_pricing!
      if item_changes.any?
        item.save!
        changes[:price_changed] << item.id if item_changes.key?(:unit_price)
        changes[:discount_changed] << item.id if item_changes.key?(:discount_percentage)
      end

      case status
      when :out_of_stock, :variant_unpublished
        changes[:out_of_stock] << cart_item_label(item)
      when :qty_overflow
        available = item.product_variant.stock_quantity.to_i
        if organisation.cart_qty_overflow_policy == "cap" && available >= 1
          item.update!(quantity: available)
          changes[:capped] << cart_item_label(item).merge(to: available)
        else
          changes[:qty_overflow] << cart_item_label(item).merge(available: available)
        end
      end
    end

    # Under the "confirm" price-change policy we persist that a change is
    # pending, so the checkout can require an explicit acknowledgement even
    # if the customer first saw the change on the cart page.
    if (changes[:price_changed].any? || changes[:discount_changed].any?) &&
       organisation.cart_price_change_policy == "confirm"
      update_column(:pricing_changed_at, Time.current)
    end

    changes
  end

  def pricing_change_pending?
    pricing_changed_at.present?
  end

  def acknowledge_pricing_change!
    update_column(:pricing_changed_at, nil) if pricing_changed_at.present?
  end

  # Line items that aren't cleanly purchasable at the requested quantity.
  def stock_issue_items
    order_items.reject { |item| item.stock_status == :purchasable }
  end

  def stock_issues?
    stock_issue_items.any?
  end

  # Enforces the organisation's checkout_stock_policy when finalising:
  #   allow → backorder, no-op
  #   block → refuse to place if any item has a stock issue
  #   warn  → refuse unless the customer ticked the confirmation checkbox
  # Runs after refresh_cart!, so items already removed/capped by the cart
  # policies are no longer counted here.
  def validate_checkout_stock!
    policy = organisation.checkout_stock_policy
    return if policy == "allow" || stock_issue_items.empty?

    if policy == "block"
      errors.add(:base, I18n.t("storefront.checkouts.errors.stock_blocked"))
      raise ActiveRecord::RecordInvalid, self
    elsif policy == "warn" && !ActiveModel::Type::Boolean.new.cast(confirmed_stock_warnings)
      errors.add(:base, I18n.t("storefront.checkouts.errors.stock_unconfirmed"))
      raise ActiveRecord::RecordInvalid, self
    end
  end

  # Under the "confirm" policy, refuse to place until the customer has
  # acknowledged a pending price/discount change (cleared via the modal).
  def validate_pricing_acknowledged!
    return unless organisation.cart_price_change_policy == "confirm"
    return unless pricing_change_pending?

    errors.add(:base, I18n.t("storefront.checkouts.errors.pricing_unconfirmed"))
    raise ActiveRecord::RecordInvalid, self
  end

  # Hard gate: refuse to place an order with any line below the product's
  # minimum order quantity. Catches legacy/grid-built carts that never passed
  # the client-side or :create-context checks.
  def validate_minimum_quantities!
    offending = order_items.select do |item|
      min = item.product&.enforced_min_quantity
      min && item.quantity.to_i < min
    end
    return if offending.empty?

    offending.each do |item|
      errors.add(:base, I18n.t("storefront.cart.below_minimum_quantity",
                               product: item.product.name,
                               minimum: item.product.minimum_quantity_label))
    end
    raise ActiveRecord::RecordInvalid, self
  end

  def finalize_checkout!(same_as_billing: false)
    self.shipping_address = billing_address if same_as_billing && billing_address.present?
    refresh_cart!
    validate_checkout_stock!
    validate_minimum_quantities!
    validate_pricing_acknowledged!
    self.tax_amount = calculated_tax
    self.shipping_amount = calculated_shipping
    snapshot_auto_discount!
    snapshot_promo_code!

    if terms_accepted_at.blank?
      errors.add(:base, "You must accept the terms and conditions")
      raise ActiveRecord::RecordInvalid, self
    end

    validate_receive_on!
    place!
  end

  def total_amount
    order_items.sum(&:total_price)
  end

  # Find the best applicable order tier discount
  def best_order_discount
    @best_order_discount ||= organisation.order_discounts
      .active
      .where("min_order_amount_cents <= ?", total_amount.cents)
      .order(min_order_amount_cents: :desc)
      .first
  end

  # Calculate the automatic order tier discount amount
  def auto_order_discount_amount
    if placed? && has_auto_discount_snapshot?
      Money.new(auto_discount_amount_cents, organisation.currency)
    elsif best_order_discount.present?
      best_order_discount.calculate_discount(total_amount)
    else
      Money.new(0, organisation.currency)
    end
  end

  def has_auto_discount_snapshot?
    auto_discount_amount_cents.present?
  end

  def auto_discount_display
    return nil unless has_auto_discount_snapshot?

    if auto_discount_type == 'percentage'
      "#{(auto_discount_value * 100).round(0)}%"
    else
      "#{organisation.currency_symbol}#{auto_discount_value}"
    end
  end

  # Total with automatic order tier discount applied (before manual discounts)
  def total_with_auto_discount
    result = total_amount - auto_order_discount_amount
    [result, Money.new(0, organisation.currency)].max
  end

  def pickup?
    delivery_method == "pickup"
  end

  def delivery?
    delivery_method == "delivery"
  end

  # Calculate shipping based on delivery method and organisation's shipping cost
  def calculated_shipping
    return Money.new(0, organisation.currency) if pickup?
    return Money.new(0, organisation.currency) if qualifies_for_free_shipping?
    organisation.shipping_cost
  end

  def qualifies_for_free_shipping?
    return false unless organisation.free_shipping_enabled?
    total_with_auto_discount >= organisation.free_shipping_threshold
  end

  def free_shipping_amount_remaining
    return nil unless organisation.free_shipping_enabled?
    return Money.new(0, organisation.currency) if qualifies_for_free_shipping?
    organisation.free_shipping_threshold - total_with_auto_discount
  end

  # Order discount methods
  def has_order_discount?
    discount_type.present? && discount_value.present?
  end

  def order_discount_amount
    return Money.new(0, organisation.currency) unless has_order_discount?

    case discount_type
    when 'percentage'
      total_amount * discount_value
    when 'fixed'
      Money.new((discount_value * 100).to_i, organisation.currency)
    else
      Money.new(0, organisation.currency)
    end
  end

  def subtotal_after_discount
    # Apply auto order tier discount, manual order discount, and promo code discount
    result = total_with_auto_discount - order_discount_amount - promo_code_discount
    [result, Money.new(0, organisation.currency)].max
  end

  def promo_code_discount
    if placed? && promo_code_discount_amount_cents.present? && promo_code_discount_amount_cents > 0
      Money.new(promo_code_discount_amount_cents, organisation.currency)
    elsif promo_code.present? && draft?
      promo_code.calculate_discount(total_with_auto_discount)
    else
      Money.new(0, organisation.currency)
    end
  end

  def has_promo_code?
    promo_code.present?
  end

  def order_discount_display
    return nil unless has_order_discount?

    if discount_type == 'percentage'
      "#{(discount_value * 100).round(0)}%"
    else
      "#{organisation.currency_symbol}#{discount_value}"
    end
  end

  # Grand total including tax and shipping
  def grand_total
    subtotal_after_discount + (tax_amount || calculated_tax) + (shipping_amount || calculated_shipping)
  end

  # Calculate tax based on subtotal after discount
  def calculated_tax
    subtotal_after_discount * organisation.tax_rate
  end

  def validate_receive_on!
    return if receive_on.blank?

    unless organisation.valid_delivery_day?(receive_on)
      errors.add(:receive_on, :invalid_delivery_day)
      raise ActiveRecord::RecordInvalid, self
    end

    if receive_on < organisation.earliest_delivery_date
      errors.add(:receive_on, :too_early)
      raise ActiveRecord::RecordInvalid, self
    end
  end

  private

  def blank_cart_changes
    { price_changed: [], discount_changed: [], removed: [], capped: [], out_of_stock: [], qty_overflow: [] }
  end

  def cart_item_label(item)
    { id: item.id, name: item.product&.name, variant: item.variant_name }
  end

  def discount_value_valid_for_type
    return unless discount_type.present? && discount_value.present?

    if discount_type == 'percentage' && discount_value > 1
      errors.add(:discount_value, "must be between 0 and 1 for percentage discounts")
    end
  end

  def generate_order_number
    return if order_number.present?

    timestamp = Time.current.strftime("%Y%m%d%H%M%S")
    sequence = organisation.orders.count + 1
    self.order_number = "#{organisation.slug.upcase}-#{timestamp}-#{sequence.to_s.rjust(4, '0')}"
  end

  def update_tax
    self.tax_amount = calculated_tax
  end

  # Fires an async push to the ERP when an order transitions into `placed`
  # state. Idempotent — the service no-ops if the order is already synced
  # or the org has ERP disabled.
  def should_enqueue_erp_push?
    saved_change_to_placed_at? && placed_at.present? && push_pending?
  end

  def enqueue_erp_push
    OrderPushJob.perform_later(id)
  end

  def snapshot_auto_discount!
    if (discount = best_order_discount)
      self.order_discount = discount
      self.auto_discount_type = discount.discount_type
      self.auto_discount_value = discount.discount_value
      self.auto_discount_amount_cents = discount.calculate_discount(total_amount).cents
    end
  end

  def snapshot_promo_code!
    return unless promo_code.present?

    result = promo_code.redeemable_by?(customer, self)
    if result != :ok
      self.promo_code = nil
      self.promo_code_discount_amount_cents = 0
      return
    end

    discount_amount = promo_code.calculate_discount(total_with_auto_discount)
    self.promo_code_discount_amount_cents = discount_amount.cents

    PromoCodeRedemption.create!(
      promo_code: promo_code,
      customer: customer,
      order: self,
      discount_amount_cents: discount_amount.cents
    )

    promo_code.class.where(id: promo_code.id)
      .update_all("usage_count = usage_count + 1")
  end
end
