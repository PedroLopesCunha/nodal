module Trackable
  extend ActiveSupport::Concern

  included do
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

  # Marking the task running belongs here, not in a before_perform callback:
  # the callback fires before `perform` runs, and every job only looks its task
  # up on the first line of `perform`, so @background_task was still nil and the
  # marking silently did nothing. Tasks stayed `pending` for their whole run and
  # `started_at` was never written — which also left a job killed mid-flight
  # (OOM, SIGKILL: no exception to rescue) indistinguishable from one that never
  # started.
  def find_task(task_id)
    @background_task = BackgroundTask.find(task_id)
    mark_running
    @background_task
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
