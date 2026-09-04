module Automations
  # "References that ran out during the period."
  #
  # Reads StockEvent, not the current stock_quantity: a reference that ran out
  # on Monday and was restocked on Wednesday still belongs in Friday's list —
  # a snapshot of today's stock would silently lose it.
  class OutOfStockDigest < Base
    def self.key = :out_of_stock_digest

    def self.filter_keys = [ :suppliers, :category_ids ]

    def columns
      [
        { key: :sku,       label: I18n.t("automations.columns.sku") },
        { key: :product,   label: I18n.t("automations.columns.product") },
        { key: :variant,   label: I18n.t("automations.columns.variant") },
        { key: :supplier,  label: I18n.t("automations.columns.supplier") },
        { key: :last_qty,  label: I18n.t("automations.columns.last_qty") },
        { key: :occurred,  label: I18n.t("automations.columns.occurred") }
      ]
    end

    def rows(period)
      scope = organisation.stock_events
                          .out_of_stock
                          .real_units
                          .in_period(period)
                          .preload(product_variant: :product)
                          .order(occurred_at: :desc)

      scope = apply_suppliers(scope)
      scope = apply_categories(scope)

      # One line per reference, not per event: a reference that flapped three
      # times in the week is still one thing to reorder. Keep the most recent.
      scope.to_a
           .uniq { |event| event.product_variant_id }
           .map { |event| build_row(event) }
    end

    private

    def apply_suppliers(scope)
      names = Array(filters[:suppliers]).map { |s| s.to_s.strip }.reject(&:blank?)
      return scope if names.empty?

      scope.where(products: { supplier: names })
    end

    def apply_categories(scope)
      ids = Array(filters[:category_ids]).map(&:to_i).reject(&:zero?)
      return scope if ids.empty?

      scope.where(products: { id: CategoryProduct.where(category_id: ids).select(:product_id) })
    end

    def build_row(event)
      variant = event.product_variant
      product = variant.product

      {
        sku: variant.sku,
        product: product.name,
        variant: variant.is_default? ? nil : variant.name,
        supplier: product.supplier,
        last_qty: event.from_quantity,
        occurred: event.occurred_at
      }
    end
  end
end
