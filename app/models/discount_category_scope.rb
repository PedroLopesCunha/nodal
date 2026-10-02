class DiscountCategoryScope < ApplicationRecord
  MODES = %w[all include exclude].freeze
  ROLES = %w[qualification discount].freeze

  belongs_to :organisation
  belongs_to :product_discount, optional: true
  belongs_to :customer_product_discount, optional: true
  belongs_to :order_discount_campaign, optional: true
  has_many :discount_category_scope_categories, dependent: :destroy, autosave: true, inverse_of: :discount_category_scope
  has_many :categories, through: :discount_category_scope_categories

  validates :mode, inclusion: { in: MODES }
  validates :role, inclusion: { in: ROLES }
  validate :valid_ownership_and_categories

  # Stage join changes in memory. Validation failures must not alter category
  # membership before the owning rule/campaign is saved.
  def stage_categories(selected)
    ids = selected.map(&:id)
    links = discount_category_scope_categories.to_a
    links.each { |link| link.mark_for_destruction unless ids.include?(link.category_id) }
    selected.each do |category|
      discount_category_scope_categories.build(category: category) unless links.any? { |link| link.category_id == category.id && !link.marked_for_destruction? }
    end
  end

  def selected_categories
    discount_category_scope_categories.reject(&:marked_for_destruction?).map(&:category).uniq
  end

  def matches_product?(product)
    return false unless product && product.organisation_id == organisation_id
    return true if mode == "all"

    matches = (product.categories.flat_map(&:path_ids).uniq & selected_category_ids).any?
    mode == "include" ? matches : !matches
  end

  def selected_category_ids
    selected_categories.map(&:id).uniq
  end

  def signature
    [mode, selected_category_ids.sort]
  end

  def product_relation
    products = organisation.products
    return products if mode == "all"
    subtree_ids = selected_categories.flat_map(&:subtree_ids).uniq
    matching = CategoryProduct.where(category_id: subtree_ids).select(:product_id)
    mode == "include" ? products.where(id: matching) : products.where.not(id: matching)
  end

  def description
    return "Todos os artigos" if mode == "all"
    prefix = mode == "include" ? "Apenas" : "Todos exceto"
    "#{prefix}: #{selected_categories.map(&:full_path).join(', ')}"
  end

  def snapshot
    { mode: mode, categories: selected_categories.map { |category| { id: category.id, name: category.full_path } } }
  end

  private

  def valid_ownership_and_categories
    owners = [product_discount, customer_product_discount, order_discount_campaign].compact
    errors.add(:base, "must have exactly one owner") unless owners.size == 1
    errors.add(:organisation, "must match owner") if owners.any? { |owner| owner.organisation_id != organisation_id }
    errors.add(:categories, "must be empty for ALL") if mode == "all" && selected_categories.any?
    errors.add(:categories, "must be selected") if mode.in?(%w[include exclude]) && selected_categories.empty?
    errors.add(:categories, "must belong to the organisation") if selected_categories.any? { |category| category.organisation_id != organisation_id }
  end
end
