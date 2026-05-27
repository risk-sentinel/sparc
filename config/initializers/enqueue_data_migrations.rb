# frozen_string_literal: true

# v1.8.3 — post-boot hook to enqueue any pending deferred data
# migrations. Runs in `Rails.application.config.after_initialize` so
# the app is fully loaded; the job itself runs in Solid Queue (which
# in production is enabled in-Puma via SOLID_QUEUE_IN_PUMA=true per
# bin/docker-entrypoint).
#
# Guards:
#   - Skip in test env (specs control enqueue explicitly)
#   - Skip when DB isn't ready (e.g., rails console with no DB,
#     asset compilation containers, etc.)
#   - Skip when there's nothing pending (no extraneous job churn)
#   - Skip if `data_migration_runs` table doesn't exist yet — this
#     initializer runs BEFORE the schema migration that creates the
#     table on a fresh install. The next deploy after the table
#     exists will pick up any pending rows.
#
# This is enqueue-only: the runner itself acquires a PG advisory
# lock so multiple ECS tasks enqueueing simultaneously won't double-
# execute.
Rails.application.config.after_initialize do
  # Only run in environments that actually want to process the
  # queue. Tests stay in control; rake tasks like assets:precompile
  # shouldn't enqueue.
  next if Rails.env.test?
  next if defined?(Rails::Console)
  next if ENV["SPARC_SKIP_DEFERRED_DATA_MIGRATIONS"] == "true"

  begin
    next unless ActiveRecord::Base.connection.table_exists?("data_migration_runs")
    pending_count = DataMigrationRun.where(status: %w[pending failed]).count
    next if pending_count.zero?

    Rails.logger.info(
      {
        deferred_data_migration: {
          phase: "enqueued",
          pending_count: pending_count,
          note: "post-boot enqueue of DeferredDataMigrationJob"
        }
      }.to_json
    )
    DeferredDataMigrationJob.perform_later
  rescue ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished, PG::ConnectionBad
    # No DB available (e.g., asset-compile-only container) — silent skip.
  rescue StandardError => e
    Rails.logger.error("[DeferredDataMigration] enqueue failed: #{e.class} — #{e.message}")
  end
end
