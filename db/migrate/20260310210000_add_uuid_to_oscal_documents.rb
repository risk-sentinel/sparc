# frozen_string_literal: true

# Adds a dedicated UUID column to all six OSCAL document tables.
# Previously, UUIDs were stored in the `import_metadata` JSONB column
# and fell back to `SecureRandom.uuid` on every export (non-deterministic).
#
# With a proper column, each document gets a stable, Postgres-generated UUID
# at creation time. Imported OSCAL documents will have their source UUID
# assigned via `assign_oscal_uuid!` in the parser services.
class AddUuidToOscalDocuments < ActiveRecord::Migration[8.1]
  TABLES = %i[
    ssp_documents
    sar_documents
    cdef_documents
    sap_documents
    poam_documents
    profile_documents
  ].freeze

  def change
    TABLES.each do |table|
      add_column table, :uuid, :string, null: false, default: -> { "gen_random_uuid()" }
      add_index  table, :uuid, unique: true
    end
  end
end
