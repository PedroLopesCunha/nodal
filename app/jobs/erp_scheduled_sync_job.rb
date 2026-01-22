class ErpScheduledSyncJob < ApplicationJob
  queue_as :erp_sync

  def perform(frequency)
    organisations_to_sync(frequency).find_each do |organisation|
      ErpSyncJob.perform_later(organisation.id, sync_type: 'scheduled')
    end
  end

  private

  def organisations_to_sync(frequency)
    Organisation
      .joins(:erp_configuration)
      .where(erp_configurations: { enabled: true, sync_frequency: frequency })
      .where.not(erp_configurations: { adapter_type: nil })
  end
end
