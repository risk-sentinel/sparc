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
    # Skip if tables already exist (running on an existing database)
    return if table_exists?(:ssp_documents)

    # Execute schema SQL directly — avoids schema.rb's define() which
    # inserts into schema_migrations and conflicts with the running migration.
    schema_file = Rails.root.join("db", "schema.rb")
    schema_content = File.read(schema_file)

    # Extract the block contents from ActiveRecord::Schema[...].define do ... end
    # and evaluate the create_table/add_index/add_foreign_key statements
    if schema_content =~ /\.define\(.*?\) do\s*$(.*)\nend\s*\z/m
      eval($1, binding, schema_file.to_s) # rubocop:disable Security/Eval
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Cannot reverse the consolidated schema migration. " \
      "Restore from backup or use the archived migrations in db/migrate_archive/."
  end
end
