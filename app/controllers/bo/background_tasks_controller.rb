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
        json[:download_url] = download_bo_background_task_path(params[:org_slug], @task) if @task.file.attached?
        render json: json
      end
    end
  end

  def download
    @task = current_organisation.background_tasks.find(params[:id])
    authorize @task, :show?

    if @task.file.attached?
      redirect_to rails_blob_path(@task.file, disposition: "attachment"), allow_other_host: true
    else
      redirect_to bo_background_task_path(params[:org_slug], @task), alert: t("bo.background_tasks.no_file")
    end
  end
end
