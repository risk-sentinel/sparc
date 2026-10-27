# frozen_string_literal: true

# #1089 — a component definition is usable by many baselines. It had one
# `profile_document_id`, so using the same component under a second baseline
# meant cloning it. This join table is now the source of truth; the column stays
# until v1.18.0 as a mirror of one linked baseline, so a rollback to v1.17.4
# still finds a baseline on every CDEF that had one.
#
# Every CDEF's existing link becomes its first row. Idempotent: the table,
# index and foreign keys are created only if absent, and the backfill skips a
# pair already present.
class CreateCdefDocumentProfileDocuments < ActiveRecord::Migration[8.1]
  def up
    create_table :cdef_document_profile_documents, if_not_exists: true do |t|
      t.bigint :cdef_document_id, null: false
      t.bigint :profile_document_id, null: false
      t.timestamps
    end

    unless index_exists?(:cdef_document_profile_documents, %i[cdef_document_id profile_document_id], name: "idx_cdef_profile_unique")
      add_index :cdef_document_profile_documents, %i[cdef_document_id profile_document_id],
                unique: true, name: "idx_cdef_profile_unique"
    end
    unless index_exists?(:cdef_document_profile_documents, :profile_document_id, name: "idx_cdef_profile_on_profile")
      add_index :cdef_document_profile_documents, :profile_document_id, name: "idx_cdef_profile_on_profile"
    end
    unless foreign_key_exists?(:cdef_document_profile_documents, :cdef_documents)
      add_foreign_key :cdef_document_profile_documents, :cdef_documents, on_delete: :cascade
    end
    unless foreign_key_exists?(:cdef_document_profile_documents, :profile_documents)
      add_foreign_key :cdef_document_profile_documents, :profile_documents, on_delete: :cascade
    end

    execute <<~SQL.squish
      INSERT INTO cdef_document_profile_documents (cdef_document_id, profile_document_id, created_at, updated_at)
      SELECT id, profile_document_id, NOW(), NOW()
      FROM cdef_documents
      WHERE profile_document_id IS NOT NULL
      ON CONFLICT (cdef_document_id, profile_document_id) DO NOTHING
    SQL
  end

  def down
    drop_table :cdef_document_profile_documents, if_exists: true
  end
end
