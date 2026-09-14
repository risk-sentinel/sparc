# frozen_string_literal: true

# ============================================================================
# MIGRATION SQUASH POINT — 2026-09-12 (Issue #1124)
# ============================================================================
#
# Third consolidation. Folds the 42 SCHEMA migrations that accumulated since
# the 2026-05-17 squash (#470) into one file describing the complete schema.
# Those files are archived to db/migrate_archive/ for reference.
#
# ── What makes THIS squash different from the previous two ─────────────────
#
# The 2026-03-19 (#183) and 2026-05-17 (#470) squashes predate deferred data
# migrations entirely: the archive ends 20260517 and the first data migration is
# 20260526. Zero data migrations were ever archived, so neither squash had to
# decide what to do with one.
#
# 23 of the 65 files carry a DeferredDataMigration — they register a backfill in
# `data_migration_runs` for DeferredDataMigrationRunner to execute after boot.
# Their effect is ROWS, not structure, so `schema.rb` cannot capture it.
#
# THE RULE THIS SQUASH FOLLOWS:
#
#     Archive a migration only when the squashed schema fully captures its
#     effect. A schema migration qualifies by definition. A data migration
#     never does.
#
# So all 23 data migrations STAY in db/migrate. That is not tidiness — it is
# load-bearing. `DeferredDataMigrationRunner#load_migration_file` resolves a
# migration class by globbing `ActiveRecord::Migrator.migrations_paths`, which
# is `["db/migrate"]` and does NOT include db/migrate_archive. Archiving one
# would mean a deployment carrying a pending or failed `DataMigrationRun` could
# never run it: the class file is gone, the ledger row remains, and nothing
# reports the gap. That is the failure mode #1124 exists to design against.
#
# ── Why this file reuses version 20260912090000 ─────────────────────────────
#
# That was `move_categorization_to_authorization_boundary`, the newest SCHEMA
# migration, now archived — so there is no collision, and three things follow:
#
#   * `schema.rb`'s `define(version:)` is unchanged, byte-identical to before.
#   * A deployment already at the released schema has this version in
#     `schema_migrations`, so it sees NO pending migration at all — not even a
#     no-op. Nothing runs, and `DataMigrationRun` is never touched.
#   * A deployment that is BEHIND runs its missing data migrations in timestamp
#     order and then this file last, where the guard below makes it a no-op.
#
# ── Fresh databases never reach this file ───────────────────────────────────
#
# `bin/docker-entrypoint` runs `db:prepare`, which LOADS schema.rb on an empty
# database rather than replaying migrations, then records every version via
# `assume_migrated_upto_version`. Worth knowing, because it also explains why a
# fresh install has no `DataMigrationRun` rows: the data migrations' `up` never
# executes there, and on an empty database there is nothing to backfill anyway.
#
#   bin/rails db:schema:load   # fast path, what db:prepare uses
#   bin/rails db:migrate       # runs this single file on an existing database
# ============================================================================
class SquashMigrationsToCurrentSchemaV2 < ActiveRecord::Migration[8.1]
  def up
    # An existing database already has the full per-migration history applied,
    # so the schema is correct and there is no work to do. Guarding on a table
    # every install has is what makes this safe to ship to production.
    return if table_exists?(:ssp_documents)

    # Execute the schema SQL directly rather than via schema.rb's `define()`,
    # which writes to schema_migrations and would conflict with the migration
    # currently running.
    schema_file = Rails.root.join("db", "schema.rb")
    schema_content = File.read(schema_file)

    if schema_content =~ /\.define\(.*?\) do\s*$(.*)\nend\s*\z/m
      eval($1, binding, schema_file.to_s) # rubocop:disable Security/Eval
    else
      raise "could not extract the schema definition block from #{schema_file}"
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "Cannot reverse the consolidated schema migration. " \
          "Restore from backup or use the archived migrations in db/migrate_archive/."
  end
end
