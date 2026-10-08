module Erp
  module Sync
    class SingleProductSyncService < ProductSyncService
      def initialize(product:, on_progress: nil)
        super(organisation: product.organisation)
        @product = product
        @on_progress = on_progress
      end

      protected

      def perform_sync
        raise Erp::ConfigurationError, 'Product sync is disabled' unless erp_configuration.can_sync_products?

        variants = @product.product_variants.where(is_default: !@product.has_variants?).to_a
        raise Erp::ApiError, 'No product variants to sync' if variants.empty?

        external_ids = variants.select { |v| v.external_source == external_source }.filter_map { |v| v.external_id.presence }.map(&:to_s).uniq
        skus = variants.filter_map { |v| v.sku.presence }.map(&:to_s).uniq
        rows = adapter.fetch_products_by_identifiers(external_ids: external_ids, skus: skus)
        @on_progress&.call(0, variants.size)

        variants.each_with_index do |variant, index|
          begin
            matches = rows.select do |row|
              variant.external_source == external_source && variant.external_id.present? && row[:external_id].to_s == variant.external_id.to_s
            end
            if matches.empty? && variant.sku.present?
              matches = rows.select { |row| row[:sku].to_s == variant.sku.to_s }
            end
            raise Erp::ApiError, 'Product not found in ERP by reference or SKU' if matches.empty?
            raise Erp::ApiError, 'Multiple ERP products match this variant' unless matches.one?

            data = matches.first
            raise Erp::ApiError, 'Missing ERP external_id' if data[:external_id].blank?

            @product.with_lock do
              variant.with_lock do
                variant.update_columns(external_id: data[:external_id], external_source: external_source)
                sync_locked_variant(variant, data)
                variant.mark_synced!(source: external_source) if variant.errors.empty?
              end
            end
          rescue StandardError => e
            variant.mark_sync_error!(e.message)
            sync_log.increment_failed!(variant.sku.presence || variant.id, e.message)
          end
          @on_progress&.call(index + 1, variants.size)
        end
      end
    end
  end
end
