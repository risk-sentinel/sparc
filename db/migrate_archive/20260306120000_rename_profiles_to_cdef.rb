class RenameProfilesToCdef < ActiveRecord::Migration[8.1]
  def change
    # ── Rename tables ──────────────────────────────────────────────
    rename_table :profile_documents,      :cdef_documents
    rename_table :profile_controls,       :cdef_controls
    rename_table :profile_control_fields, :cdef_control_fields

    # ── Rename foreign-key columns ─────────────────────────────────
    rename_column :cdef_controls,       :profile_document_id, :cdef_document_id
    rename_column :cdef_control_fields, :profile_control_id,  :cdef_control_id

    # ── Rename domain columns ──────────────────────────────────────
    rename_column :cdef_documents, :profile_type,    :cdef_type
    rename_column :cdef_documents, :profile_version, :cdef_version

    # ── Rename indexes for consistency ─────────────────────────────
    # PostgreSQL may auto-rename some indexes when tables are renamed,
    # so we use reversible execute blocks with safe IF EXISTS guards.
    reversible do |dir|
      dir.up do
        execute <<~SQL
          ALTER INDEX IF EXISTS index_profile_documents_on_created_at   RENAME TO index_cdef_documents_on_created_at;
          ALTER INDEX IF EXISTS index_profile_documents_on_profile_type RENAME TO index_cdef_documents_on_cdef_type;
          ALTER INDEX IF EXISTS index_profile_documents_on_status       RENAME TO index_cdef_documents_on_status;

          ALTER INDEX IF EXISTS index_profile_controls_on_profile_document_id RENAME TO index_cdef_controls_on_cdef_document_id;
          ALTER INDEX IF EXISTS idx_profile_controls_on_doc_family            RENAME TO idx_cdef_controls_on_doc_family;
          ALTER INDEX IF EXISTS idx_profile_controls_on_doc_row               RENAME TO idx_cdef_controls_on_doc_row;

          ALTER INDEX IF EXISTS index_profile_control_fields_on_profile_control_id RENAME TO index_cdef_control_fields_on_cdef_control_id;
          ALTER INDEX IF EXISTS idx_profile_fields_on_ctrl_name                    RENAME TO idx_cdef_fields_on_ctrl_name;
        SQL
      end

      dir.down do
        execute <<~SQL
          ALTER INDEX IF EXISTS index_cdef_documents_on_created_at   RENAME TO index_profile_documents_on_created_at;
          ALTER INDEX IF EXISTS index_cdef_documents_on_cdef_type    RENAME TO index_profile_documents_on_profile_type;
          ALTER INDEX IF EXISTS index_cdef_documents_on_status       RENAME TO index_profile_documents_on_status;

          ALTER INDEX IF EXISTS index_cdef_controls_on_cdef_document_id RENAME TO index_profile_controls_on_profile_document_id;
          ALTER INDEX IF EXISTS idx_cdef_controls_on_doc_family         RENAME TO idx_profile_controls_on_doc_family;
          ALTER INDEX IF EXISTS idx_cdef_controls_on_doc_row            RENAME TO idx_profile_controls_on_doc_row;

          ALTER INDEX IF EXISTS index_cdef_control_fields_on_cdef_control_id RENAME TO index_profile_control_fields_on_profile_control_id;
          ALTER INDEX IF EXISTS idx_cdef_fields_on_ctrl_name                 RENAME TO idx_profile_fields_on_ctrl_name;
        SQL
      end
    end
  end
end
