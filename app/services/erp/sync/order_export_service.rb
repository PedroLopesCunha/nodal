module Erp
  module Sync
    # Batch pusher: iterates orders in `pushable` state and delegates each
    # to `Erp::OrderPushService`. Used as the safety-net when the per-order
    # job failed or wasn't enqueued. Logs aggregated results to ErpSyncLog.
    class OrderExportService < BaseSyncService
      protected

      def entity_type
        'orders'
      end

      def perform_sync
        unless adapter.supports_push?
          raise Erp::ApiError, "Adapter '#{adapter.adapter_name}' does not support pushing orders"
        end

        organisation.orders.pushable.find_each do |order|
          push_single(order)
        end
      end

      private

      def push_single(order)
        result = Erp::OrderPushService.new(order: order).call

        if result.success?
          if result.idempotent
            sync_log.increment_updated!
          else
            sync_log.increment_created!
          end
        else
          sync_log.increment_failed!(order.order_number, result.error)
        end
      end
    end
  end
end
