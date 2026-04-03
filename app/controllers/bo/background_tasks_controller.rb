class Bo::BackgroundTasksController < Bo::BaseController
  def index
    authorize BackgroundTask
    @tasks = current_organisation.background_tasks
      .where(member: current_member)
      .recent
      .limit(20)
  end

  def show
    @task = current_organisation.background_tasks.find(params[:id])
    authorize @task

    respond_to do |format|
      format.html
      format.json do
        render json: {
          status: @task.status,
          progress: @task.progress,
          total: @task.total,
          progress_percentage: @task.progress_percentage,
          result: @task.result,
          error_message: @task.error_message
        }
      end
    end
  end
end
