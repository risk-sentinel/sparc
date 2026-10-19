# frozen_string_literal: true

# #1223 — runs deferred data migrations that are still waiting BETWEEN boots.
#
# The boot enqueue (config/initializers/enqueue_data_migrations.rb) fires once.
# During a rolling deploy the previous release's worker can take that job, fail
# to load the new release's migration class, and mark the row `failed` — and
# releases already shipped will keep doing that whatever this one does. Nothing
# re-enqueued until the next boot, which in a deployment that hibernates
# overnight could be many hours.
#
# Scheduled every 5 minutes (config/recurring.yml). It does nothing unless a
# row is awaiting this release (`DataMigrationRun.awaiting_this_release`): a
# genuine failure still retries once per boot, not every 5 minutes. While the
# old task drains its worker may still take this job; once it is gone, this
# release's worker runs the rows within one interval.
#
# NIST SP 800-53 Rev 5: CM-3 (configuration change control), SI-2.
class DeferredDataMigrationSweepJob < ApplicationJob
  queue_as :default

  # Same policy as DeferredDataMigrationJob: the row lifecycle is the record,
  # and the next sweep is the retry.
  retry_on StandardError, attempts: 1, wait: 0.seconds

  def perform
    return if DataMigrationRun.awaiting_this_release.empty?

    DeferredDataMigrationRunner.run_all_pending
  end
end
