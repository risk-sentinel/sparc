# frozen_string_literal: true

# v1.8.3 — Solid Queue job that runs pending deferred data migrations
# post-boot. Enqueued by `config/initializers/enqueue_data_migrations.rb`
# after Rails finishes booting (so we don't block Puma binding).
#
# Idempotent: the runner acquires a PG advisory lock; concurrent
# enqueues from multiple containers all serialize through that lock
# and the loser ones return quickly with a "lock held elsewhere"
# log line — no work happens twice.
#
# Re-runs on failure: this job does NOT retry on its own. The runner
# records the failure in DataMigrationRun.status = "failed"; the
# next container boot's initializer re-enqueues and the runner will
# retry the failed row. Letting failures sit visible in the admin
# table > silent ActiveJob retries.
class DeferredDataMigrationJob < ApplicationJob
  queue_as :default

  # Disable automatic retry — the runner handles retry logic via
  # the DataMigrationRun lifecycle.
  retry_on StandardError, attempts: 1, wait: 0.seconds

  def perform
    DeferredDataMigrationRunner.run_all_pending
  end
end
