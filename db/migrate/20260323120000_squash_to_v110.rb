# frozen_string_literal: true

# Pre-release migration squash — consolidates all schema changes through v1.1.0
# into a single migration. This replaces 73 individual migrations (64 original +
# 9 post-squash) with one clean entry point.
#
# For FRESH databases: evaluates db/schema.rb to create all 72 tables in one shot.
# For EXISTING databases: no-op (tables already exist from running individual migrations).
#
# Seeds (db/seeds.rb) are completely independent — they use SeedRunner with its own
# version tracking and are called separately from bin/docker-entrypoint.
#
# NIST SA-10: Developer Configuration Management
class SquashToV110 < ActiveRecord::Migration[8.1]
  def up
    # Existing databases already have all tables — skip entirely
    return if table_exists?(:ssp_documents)

    # Fresh database — load the entire schema in one shot from schema.rb
    puts "[SquashToV110] Fresh database detected — loading full schema..."
    schema = File.read(Rails.root.join("db/schema.rb"))

    # Strip the ActiveRecord::Schema wrapper, leaving just the create_table/add_index calls
    schema_body = schema.gsub(/\A.*ActiveRecord::Schema\[[\d.]+\]\.define\(version: \d+_\d+_\d+\) do/m, "")
    schema_body = schema_body.gsub(/\nend\s*\z/m, "")

    eval(schema_body) # rubocop:disable Security/Eval

    puts "[SquashToV110] Schema loaded — #{ActiveRecord::Base.connection.tables.count} tables created."
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "This migration consolidates all schema changes through SPARC v1.1.0. " \
          "To revert, restore from a database backup."
  end
end
