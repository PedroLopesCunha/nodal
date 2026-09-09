require "test_helper"

class TrackableTest < ActiveJob::TestCase
  # Mirrors how the real jobs use the concern: task_id first, looked up on the
  # first line of perform.
  class TrackedTestJob < ApplicationJob
    include Trackable

    cattr_accessor :observed_status

    def perform(task_id, fail: false)
      find_task(task_id)
      self.class.observed_status = BackgroundTask.find(task_id).status
      raise "boom" if fail
    end
  end

  setup do
    TrackedTestJob.observed_status = nil

    @organisation = Organisation.create!(
      name: "Test Org", slug: "test-org-#{SecureRandom.hex(4)}",
      currency: "EUR", tax_rate: 0.23, timezone: "Europe/Lisbon"
    )
    @member = Member.create!(
      email: "member-#{SecureRandom.hex(4)}@exemplo.pt",
      password: "password123", first_name: "Ana", last_name: "Silva"
    )
    @task = BackgroundTask.create!(
      organisation: @organisation, member: @member, task_type: "export"
    )
  end

  # The regression guard. `running` used to be unreachable: before_perform fired
  # while @background_task was still nil, so every task sat at `pending` for its
  # whole run. Asserting the final state would miss it — the state has to be
  # observed from inside perform, while the job is actually working.
  test "marks the task running while it works" do
    TrackedTestJob.perform_now(@task.id)

    assert_equal "running", TrackedTestJob.observed_status
  end

  test "records when the work started" do
    TrackedTestJob.perform_now(@task.id)

    assert_not_nil @task.reload.started_at
  end

  test "a completed task can report how long it took" do
    TrackedTestJob.perform_now(@task.id)

    assert_equal "completed", @task.reload.status
    assert_not_nil @task.duration, "duration needs started_at, which mark_running writes"
  end

  test "a task that raises ends up failed with the error" do
    assert_raises(RuntimeError) { TrackedTestJob.perform_now(@task.id, fail: true) }

    @task.reload
    assert_equal "failed", @task.status
    assert_equal "boom", @task.error_message
    assert_not_nil @task.started_at
  end
end
