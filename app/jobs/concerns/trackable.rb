module Trackable
  extend ActiveSupport::Concern

  included do
    before_perform :mark_running
    after_perform :mark_completed

    rescue_from(StandardError) do |exception|
      if @background_task
        @background_task.update!(
          status: :failed,
          error_message: exception.message,
          completed_at: Time.current
        )
      end
      raise exception
    end
  end

  private

  def find_task(task_id)
    @background_task = BackgroundTask.find(task_id)
  end

  def mark_running
    return unless @background_task
    @background_task.update!(status: :running, started_at: Time.current)
  end

  def mark_completed
    return unless @background_task
    @background_task.update!(status: :completed, completed_at: Time.current)
  end

  def update_progress(progress, total = nil)
    return unless @background_task
    attrs = { progress: progress }
    attrs[:total] = total if total
    @background_task.update_columns(attrs)
  end

  def save_result(result)
    return unless @background_task
    @background_task.update_columns(result: result)
  end
end
