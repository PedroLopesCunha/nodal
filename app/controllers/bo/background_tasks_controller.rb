class Bo::BackgroundTasksController < Bo::BaseController
  def index
    @tasks = policy_scope(BackgroundTask)
      .where(member: current_member)
      .recent
      .limit(20)
  end

  def show
    @task = current_organisation.background_tasks.find(params[:id])
    authorize @task
    @task.update_column(:viewed_at, Time.current) if @task.viewed_at.nil? && @task.status.in?(%w[completed failed])

    respond_to do |format|
      format.html
      format.json do
        json = {
          status: @task.status,
          progress: @task.progress,
          total: @task.total,
          progress_percentage: @task.progress_percentage,
          result: @task.result,
          error_message: @task.error_message
        }
        # Catalog PDFs are stored directly in Cloudinary (raw), other tasks use ActiveStorage
        if @task.result.is_a?(Hash) && @task.result["download_url"].present?
          json[:download_url] = @task.result["download_url"]
        elsif @task.file.attached?
          json[:download_url] = download_bo_background_task_path(params[:org_slug], @task)
        end
        render json: json
      end
    end
  end

  def download
    @task = current_organisation.background_tasks.find(params[:id])
    authorize @task, :show?

    if @task.file.attached?
      send_data @task.file.download,
        filename: @task.file.filename.to_s,
        content_type: @task.file.content_type,
        disposition: "attachment"
    else
      redirect_to bo_background_task_path(params[:org_slug], @task), alert: t("bo.background_tasks.no_file")
    end
  end
end
