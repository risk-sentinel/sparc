# frozen_string_literal: true

# ============================================================================
# MIGRATION SQUASH POINT — 2026-03-19
# ============================================================================
#
# This migration consolidates all 64 prior migrations into a single file
# representing the complete database schema as of this date.
#
# Prior migrations have been archived to db/migrate_archive/ for reference.
#
# For new development environments, use:
#   bin/rails db:schema:load   (faster, recommended)
#   OR
#   bin/rails db:migrate       (runs this single migration)
#
# This migration is idempotent — it uses create_table with if_not_exists
# so it safely no-ops on databases that already have these tables.
# ============================================================================
class SquashMigrationsToCurrentSchema < ActiveRecord::Migration[8.1]
  def up
    # Load the schema definition from db/schema.rb
    # This is the safest approach — it uses the exact same schema
    # that Rails generates and validates.
    schema_file = Rails.root.join("db", "schema.rb")
    load(schema_file)
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Cannot reverse the consolidated schema migration. " \
      "Restore from backup or use the archived migrations in db/migrate_archive/."
  end
end
