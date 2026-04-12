class AddProfileDocumentIdToCdefDocuments < ActiveRecord::Migration[8.0]
  def change
    unless column_exists?(:cdef_documents, :profile_document_id)
      add_reference :cdef_documents, :profile_document,
                    null: true,
                    foreign_key: { to_table: :profile_documents, on_delete: :nullify }
    end

    # Backfill profile_document_id from import_metadata for CDEFs created from profiles
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE cdef_documents
          SET profile_document_id = (import_metadata->>'source_profile_id')::bigint
          WHERE import_metadata->>'source_type' = 'profile'
            AND profile_document_id IS NULL
            AND (import_metadata->>'source_profile_id') IS NOT NULL
        SQL
      end
    end
  end
end
