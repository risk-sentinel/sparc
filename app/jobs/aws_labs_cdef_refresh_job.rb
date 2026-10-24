# Issue #466 — Solid Queue recurring job that refreshes the AWS Labs CDEF
# catalog. Gating is enforced inside the service (no-op when the env var is
# off) so the job class itself can be safely enqueued in any environment.
#
# #1268 — every run records that it started and how it ended, in the audit
# log, so the CDEF screen can say what the last refresh did (AwsLabsRefreshStatus).
# Before, a refresh that imported nothing looked like one that never ran.
class AwsLabsCdefRefreshJob < ApplicationJob
  queue_as :default

  def perform(force: false)
    record("aws_labs_cdef_refresh_started", force: force)
    result = AwsLabsCdefImportService.new.run(force: force)
    Rails.logger.info("[AwsLabsCdefRefreshJob] #{result}")
    record(result.kept_nothing? ? "aws_labs_cdef_refresh_kept_nothing" : "aws_labs_cdef_refresh_completed",
           force: force, discovered: result.discovered, kept: result.kept, imported: result.imported,
           skipped_unchanged: result.skipped_unchanged, superseded: result.superseded,
           errors: result.errors.length, skipped_by_version: result.skipped_by_version,
           allowed_versions: result.allowed_versions)
    result
  rescue StandardError => e
    record("aws_labs_cdef_refresh_failed", force: force, error_class: e.class.to_s, error_message: e.message.to_s[0, 300])
    raise
  end

  private

  # Recording must never be the reason a refresh fails.
  def record(action, **metadata)
    AuditEvent.log(action: action, metadata: metadata.merge(job_id: job_id).compact)
  rescue StandardError => e
    Rails.logger.warn("[AwsLabsCdefRefreshJob] Could not record #{action}: #{e.class}: #{e.message}")
  end
end
