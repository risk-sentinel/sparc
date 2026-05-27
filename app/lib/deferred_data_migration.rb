# frozen_string_literal: true

# Mark an ActiveRecord::Migration as a *deferred* data migration — its
# body runs *after* the container boots, inside a Solid Queue job, not
# during `db:prepare` (v1.8.3).
#
# Two execution contexts:
#
#   1. `db:migrate` (sparc:db_prepare → entrypoint, sync):
#      `defer_data_migration { ... }` registers a pending
#      `DataMigrationRun` row and RETURNS without running the block.
#      The schema_migrations row gets recorded as normal (so Rails
#      considers the migration "applied"), but the actual data work
#      is queued for the runner.
#
#   2. Runner (`DeferredDataMigrationRunner` invoked by
#      `DeferredDataMigrationJob`, async):
#      Sets `DeferredDataMigration.executing!` for the thread,
#      invokes the migration's `up` method, which routes through
#      `defer_data_migration` — this time the block IS executed.
#      Runner updates the tracking row to running → completed/failed
#      around the block.
#
# Usage in a migration file:
#
#   class PromoteFooBackMatter < ActiveRecord::Migration[8.1]
#     include DeferredDataMigration
#     data_migration_version "1.0.0"
#
#     def up
#       defer_data_migration do
#         Foo.find_each { |f| ... }
#       end
#     end
#
#     def down
#       raise ActiveRecord::IrreversibleMigration
#     end
#   end
#
module DeferredDataMigration
  extend ActiveSupport::Concern

  # Thread-local flag set by the runner so a migration's block knows
  # it's being executed (not just registered). Per-thread is important
  # — Solid Queue worker threads must each see their own value.
  thread_mattr_accessor :executing

  class_methods do
    # Optional: stamp a semver-ish version on the migration so an
    # admin can force a re-run later (`DataMigrationRun#version`
    # comparison). Defaults to "1.0.0".
    def data_migration_version(value = nil)
      @data_migration_version = value if value
      @data_migration_version || "1.0.0"
    end
  end

  # Sentinel exception the runner uses to distinguish a registered
  # but not-yet-executed migration from a true error. NEVER raised
  # in production code paths — only by the registration branch when
  # called from a misconfigured runner.
  class DeferredRegistrationOnly < StandardError; end

  # Block dispatcher. In runner context: executes the block. In
  # db:migrate context: registers a pending DataMigrationRun (or
  # leaves an existing row alone) and returns.
  def defer_data_migration(&block)
    raise ArgumentError, "block required" unless block

    if DeferredDataMigration.executing
      block.call
    else
      register_pending_run!
    end
  end

  # Class-method accessor for the runner so it can flip the flag
  # without needing to know the thread plumbing.
  def self.executing!
    self.executing = true
  end

  def self.idle!
    self.executing = false
  end

  private

  # Idempotent: re-registering is a no-op when the row already exists
  # in any state. We never overwrite an existing run's status here —
  # the runner owns lifecycle transitions.
  def register_pending_run!
    name    = self.class.name
    version = self.class.data_migration_version
    DataMigrationRun.find_or_create_by!(name: name) do |run|
      run.version = version
      run.status  = "pending"
    end
  end
end
