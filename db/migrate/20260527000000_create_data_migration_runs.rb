# v1.8.3 — tracking table for deferred data migrations.
#
# A row per migration class marked with `include DeferredDataMigration`.
# The deferred runner (Solid Queue job) reads `pending` rows, executes
# each migration's block, updates the row to `running` → `completed` /
# `failed`. The admin status page reads from this table.
#
# Schema-only migration, runs synchronously at deploy time (fast).
class CreateDataMigrationRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :data_migration_runs do |t|
      t.string   :name,              null: false   # migration class name
      t.string   :version,           default: "1.0.0"
      t.string   :status,            default: "pending", null: false
      t.datetime :started_at
      t.datetime :completed_at
      t.integer  :records_processed, default: 0, null: false
      t.text     :error_message
      t.timestamps
    end

    add_index :data_migration_runs, :name,   unique: true
    add_index :data_migration_runs, :status
  end
end
