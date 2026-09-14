# frozen_string_literal: true

# Issue #537 — recovers the `cloned_from_id` column on `cdef_documents` for
# databases that were upgraded across the #470 migration squash without
# running the original #466 migration (20260517144141).
#
# The squash migration's idempotent guard (`return if table_exists?(:ssp_documents)`)
# short-circuits whole-schema setup on existing DBs, but doesn't probe for
# individual columns added between the previous squash point and itself. Any
# deployment that jumped from a pre-#466 build straight to >= #470 is missing
# this column, and every CDEF API verb crashes on `serialize_cdef`'s reference
# to `cdef.cloned_from_id`.
#
# Safe on already-correct databases: every operation is guarded.
class RestoreClonedFromIdOnCdefDocuments < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:cdef_documents, :cloned_from_id)
      add_reference :cdef_documents,
        :cloned_from,
        null: true,
        foreign_key: { to_table: :cdef_documents }
    end

    reversible do |dir|
      dir.up do
        execute <<~SQL
          CREATE UNIQUE INDEX IF NOT EXISTS idx_cdef_docs_aws_labs_source_unique
            ON cdef_documents ((import_metadata->>'source_url'), (import_metadata->>'source_sha'))
            WHERE import_metadata->>'source_type' = 'aws_labs'
        SQL
      end

      dir.down do
        execute "DROP INDEX IF EXISTS idx_cdef_docs_aws_labs_source_unique"
      end
    end
  end
end
