class ErpProductSyncJob < ApplicationJob
  include Trackable

  queue_as :erp_sync

  def perform(task_id, product_id:)
    task = find_task(task_id)
    product = task.organisation.products.find(product_id)
    begin
      result = Erp::Sync::SingleProductSyncService.new(product: product,
        on_progress: ->(progress, total) { update_progress(progress, total) }).call
    rescue ActiveRecord::Encryption::Errors::Decryption
      raise Erp::ConfigurationError, I18n.t('bo.products.erp_sync.invalid_credentials')
    end
    checkpoint!
    log = result.sync_log
    save_result(product_id: product.id, stats: { updated: log&.records_updated, record_count: log&.records_processed },
                errors: log&.error_details || [])
    raise Erp::ApiError, result.error unless result.success?
    if log.records_failed.positive?
      raise Erp::ApiError, log.error_details.map { |error| error['error'] || error[:error] }.join('; ')
    end
  end
end
