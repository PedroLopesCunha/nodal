class OrderDiscount < ApplicationRecord
  include HasEmailNotification

  DISCOUNT_TYPES = %w[percentage fixed].freeze

  belongs_to :organisation
  belongs_to :order_discount_campaign, optional: true
  before_validation :assign_legacy_campaign
  validate :campaign_organisation_matches
  validate :unique_overlapping_tier

  monetize :min_order_amount_cents

  validates :discount_type, presence: true, inclusion: { in: DISCOUNT_TYPES }
  validates :discount_value, presence: true, numericality: { greater_than: 0 }
  validates :min_order_amount_cents, presence: true, numericality: { greater_than: 0 }

  validate :discount_value_valid_for_type
  validate :valid_until_after_valid_from

  scope :active, -> {
    where(active: true)
      .where("(valid_from IS NULL OR valid_from <= ?) AND (valid_until IS NULL OR valid_until >= ?)",
             Date.current, Date.current)
  }

  scope :by_min_amount, -> { order(min_order_amount_cents: :asc) }

  def percentage?
    discount_type == 'percentage'
  end

  def fixed?
    discount_type == 'fixed'
  end

  def perpetual?
    valid_from.nil? && valid_until.nil?
  end

  def value_display
    if percentage?
      "#{(discount_value * 100).round(0)}%"
    else
      discount_value
    end
  end

  def min_amount_display
    min_order_amount.format
  end

  def valid_period_display
    if perpetual?
      "No expiry"
    elsif valid_from.present? && valid_until.present?
      "#{valid_from.strftime('%Y-%m-%d')} to #{valid_until.strftime('%Y-%m-%d')}"
    elsif valid_from.present?
      "From #{valid_from.strftime('%Y-%m-%d')}"
    elsif valid_until.present?
      "Until #{valid_until.strftime('%Y-%m-%d')}"
    end
  end

  def evaluation_for(order)
    OrderDiscountEvaluator.new(order).evaluate(self)
  end

  def display_name
    "#{order_discount_campaign&.name || 'Escalão'} · #{min_amount_display} → #{value_display}"
  end

  def calculate_discount(order_total)
    return Money.new(0, organisation.currency) unless order_total >= min_order_amount

    if percentage?
      order_total * discount_value
    else
      Money.new((discount_value * 100).to_i, organisation.currency)
    end
  end

  def applicable_to?(order_total)
    order_total >= min_order_amount
  end

  private

  def assign_legacy_campaign
    return if order_discount_campaign || !organisation
    organisation.with_lock do
      self.order_discount_campaign = organisation.order_discount_campaigns.find_by(legacy: true) ||
        organisation.order_discount_campaigns.create!(name: "Escalões existentes", legacy: true,
          priority: (organisation.order_discount_campaigns.maximum(:priority) || 0) + 1)
    end
  end

  def campaign_organisation_matches
    if order_discount_campaign && order_discount_campaign.organisation_id != organisation_id
      errors.add(:order_discount_campaign, "must belong to the organisation")
    end
  end

  def unique_overlapping_tier
    return if !active? || !order_discount_campaign || order_discount_campaign.legacy?
    candidates = order_discount_campaign.order_discounts.where(active: true, min_order_amount_cents: min_order_amount_cents).where.not(id: id)
    candidates = candidates.where("valid_until IS NULL OR valid_until >= ?", valid_from) if valid_from
    candidates = candidates.where("valid_from IS NULL OR valid_from <= ?", valid_until) if valid_until
    errors.add(:min_order_amount, "overlaps with another active tier in this campaign") if candidates.exists?
  end

  def discount_value_valid_for_type
    return unless discount_value.present? && discount_type.present?

    if percentage? && discount_value > 1
      errors.add(:discount_value, "must be between 0 and 1 for percentage discounts (e.g., 0.15 for 15%)")
    end
  end

  def valid_until_after_valid_from
    return if valid_from.blank? || valid_until.blank?

    if valid_until < valid_from
      errors.add(:valid_until, "must be after valid from date")
    end
  end
end
