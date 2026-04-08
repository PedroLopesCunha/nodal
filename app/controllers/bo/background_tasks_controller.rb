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
        result = @task.result || {}
        if result["cloudinary_url"].present? || @task.file.attached?
          json[:download_url] = download_bo_background_task_path(params[:org_slug], @task)
        end
        render json: json
      end
    end
  end

  def download
    @task = current_organisation.background_tasks.find(params[:id])
    authorize @task, :show?

    result = @task.result || {}

    if result["cloudinary_url"].present?
      redirect_to result["cloudinary_url"], allow_other_host: true
    elsif @task.file.attached?
      send_data @task.file.download,
        filename: @task.file.filename.to_s,
        content_type: @task.file.content_type,
        disposition: "attachment"
    else
      redirect_to bo_background_task_path(params[:org_slug], @task), alert: t("bo.background_tasks.no_file")
    end
  end
end
