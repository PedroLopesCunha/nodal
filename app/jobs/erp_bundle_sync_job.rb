class ErpBundleSyncJob < ApplicationJob
  include Trackable

  queue_as :erp_sync

  def perform(task_id, product_id:)
    task = find_task(task_id)
    bundle = task.organisation.products.bundles.find(product_id)
    parts = bundle.bundle_components.includes(product_variant: :product).to_a
    errors = []
    updated = 0
    processed = 0
    update_progress(0, parts.size)
    parts.group_by { |part| part.product_variant.product }.each do |product, components|
      checkpoint!
      result = Erp::Sync::SingleProductSyncService.new(product: product,
        variant_ids: components.map(&:product_variant_id)).call
      log = result.sync_log
      updated += log&.records_updated.to_i
      processed += log&.records_processed.to_i
      errors.concat(log&.error_details || [])
      errors << { product_id: product.id, error: result.error } unless result.success?
      update_progress([@background_task.progress + components.size, parts.size].min, parts.size)
    end
    bundle.reload.refresh_bundle_inventory!
    save_result(product_id: bundle.id, bundle_id: bundle.id, stats: { updated: updated, record_count: processed }, errors: errors)
    raise Erp::ApiError, errors.map { |error| error['error'] || error[:error] }.compact.join('; ') if errors.any?
  rescue ActiveRecord::Encryption::Errors::Decryption
    raise Erp::ConfigurationError, I18n.t('bo.products.erp_sync.invalid_credentials')
  end
end
