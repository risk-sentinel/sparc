# frozen_string_literal: true

module Admin
  # v1.8.3 — read-only admin view of the deferred-data-migration
  # tracking table. Shows what's pending, running, completed, or
  # failed; lets the operator see post-boot data-migration progress
  # without grepping logs.
  #
  # No actions besides display. To re-trigger / reset a row, use
  # `bin/rake sparc:data_migrations:run` /
  # `bin/rake sparc:data_migrations:reset NAME=ClassName` from a
  # one-off ECS task or Rails console.
  class DataMigrationsController < ApplicationController
    before_action :authorize_admin!

    def index
      @data_migration_runs = DataMigrationRun.recent
      @counts = {
        pending:   @data_migration_runs.count(&:pending?),
        running:   @data_migration_runs.count(&:running?),
        completed: @data_migration_runs.count(&:completed?),
        failed:    @data_migration_runs.count(&:failed?)
      }
    end
  end
end
