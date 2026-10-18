# frozen_string_literal: true

# v1.8.3 — post-boot hook to enqueue any pending deferred data
# migrations. Runs in `Rails.application.config.after_initialize` so
# the app is fully loaded; the job itself runs in Solid Queue (which
# in production is enabled in-Puma via SOLID_QUEUE_IN_PUMA=true per
# bin/docker-entrypoint).
#
# Guards (in DeferredDataMigrationRunner.enqueue_after_boot, where they are
# specced):
#   - Skip in test env (specs control enqueue explicitly)
#   - #1223: enqueue from the WEB SERVER boot only. Every `bin/rails` task
#     boots the app too, and bin/docker-entrypoint runs four before Puma
#     starts (db:prepare, db:reconcile_schema, sparc:bootstrap_admin,
#     db:seed). Those containers have no worker yet, so during a rolling
#     deploy only the PREVIOUS release could take each job — and it marked the
#     new release's rows failed, about every 3 seconds. That also covers the
#     console, which the old `Rails::Console` check guarded.
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

  DeferredDataMigrationRunner.enqueue_after_boot(server: defined?(Rails::Server).present?)
end
