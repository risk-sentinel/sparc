class AddSspDocumentIdToPoamDocuments < ActiveRecord::Migration[8.1]
  # #395 P2: POA&M needs an ssp_document_id FK so the BoundaryLinkInheritance
  # callback + OSCAL `import-ssp.href` resolution can wire POA&M items back
  # to their SSP. Today the link only exists in `import_metadata["import_ssp"]`
  # as a raw href.
  def up
    unless column_exists?(:poam_documents, :ssp_document_id)
      add_reference :poam_documents, :ssp_document,
                    null: true, foreign_key: { on_delete: :nullify }, index: true
    end
  end

  def down
    if column_exists?(:poam_documents, :ssp_document_id)
      remove_foreign_key :poam_documents, column: :ssp_document_id rescue nil
      remove_reference   :poam_documents, :ssp_document, index: true
    end
  end
end
