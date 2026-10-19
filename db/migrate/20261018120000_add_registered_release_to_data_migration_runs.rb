# frozen_string_literal: true

# #1223 — which release registered a deferred data migration.
#
# During a rolling deploy the previous release's worker can pick up a job the
# new release enqueued. It cannot load a migration class it has never seen, and
# it used to mark the row `failed`. With the registering release recorded, a
# runner that finds no migration file can tell the two cases apart: a row from
# a NEWER release is left `pending` for that release to run, and a row from
# this release or an older one (an archived migration) still fails, so it can
# never wait forever.
#
# Nullable, no default, no backfill: rows registered before this column are
# unknown, and the runner treats them exactly as it did before.
class AddRegisteredReleaseToDataMigrationRuns < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:data_migration_runs, :registered_release)
      add_column :data_migration_runs, :registered_release, :string
    end
    # A deferred migration later in this same db:migrate run registers its row
    # through the model; make sure the model sees the new column.
    DataMigrationRun.reset_column_information
  end

  def down
    remove_column :data_migration_runs, :registered_release, if_exists: true
  end
end
