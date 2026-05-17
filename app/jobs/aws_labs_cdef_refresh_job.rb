# Issue #466 — Solid Queue recurring job that refreshes the AWS Labs CDEF
# catalog. Gating is enforced inside the service (no-op when the env var is
# off) so the job class itself can be safely enqueued in any environment.
class AwsLabsCdefRefreshJob < ApplicationJob
  queue_as :default

  def perform(force: false)
    result = AwsLabsCdefImportService.new.run(force: force)
    Rails.logger.info("[AwsLabsCdefRefreshJob] #{result}")
    result
  end
end
