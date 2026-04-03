class Bo::BackgroundTasksController < Bo::BaseController
  def show
    @task = current_organisation.background_tasks.find(params[:id])

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
