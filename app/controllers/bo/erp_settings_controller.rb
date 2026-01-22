class Bo::ErpSettingsController < Bo::BaseController
  skip_before_action :verify_authenticity_token, only: [:test_connection]
  before_action :set_erp_configuration

  def edit
    authorize @erp_configuration, policy_class: ErpSettingPolicy
    @available_adapters = Erp::AdapterRegistry.available_adapters
    @recent_sync_logs = @erp_configuration.erp_sync_logs.recent.limit(5) if @erp_configuration.persisted?
  end

  def update
    authorize @erp_configuration, policy_class: ErpSettingPolicy

    if @erp_configuration.update(erp_configuration_params)
      redirect_to edit_bo_erp_settings_path(org_slug: current_organisation.slug),
                  notice: "ERP settings updated successfully."
    else
      @available_adapters = Erp::AdapterRegistry.available_adapters
      render :edit, status: :unprocessable_entity
    end
  end

  def test_connection
    authorize @erp_configuration, policy_class: ErpSettingPolicy

    if @erp_configuration.adapter.nil?
      render json: { success: false, error: 'No adapter configured' }
      return
    end

    result = @erp_configuration.adapter.test_connection

    render json: result
  end

  def sync_now
    authorize @erp_configuration, policy_class: ErpSettingPolicy

    unless @erp_configuration.can_sync?
      redirect_to edit_bo_erp_settings_path(org_slug: current_organisation.slug),
                  alert: "Cannot sync: ERP integration is not properly configured."
      return
    end

    ErpSyncJob.perform_later(current_organisation.id, sync_type: 'manual')

    redirect_to edit_bo_erp_settings_path(org_slug: current_organisation.slug),
                notice: "Sync started. Check the sync logs for progress."
  end

  def sync_logs
    authorize @erp_configuration, policy_class: ErpSettingPolicy

    @sync_logs = current_organisation.erp_sync_logs.recent.limit(50)
  end

  private

  def set_erp_configuration
    @erp_configuration = current_organisation.erp_configuration ||
                         current_organisation.build_erp_configuration
  end

  def erp_configuration_params
    params.require(:erp_configuration).permit(
      :enabled,
      :adapter_type,
      :sync_products,
      :sync_customers,
      :sync_orders,
      :sync_frequency,
      credentials: {}
    ).tap do |p|
      if p[:credentials].present?
        @erp_configuration.credentials = p.delete(:credentials).to_h
      end
    end
  end
end
