class AddProfileAndSspToSarDocuments < ActiveRecord::Migration[8.0]
  def change
    add_reference :sar_documents, :profile_document, foreign_key: true, null: true
    add_reference :sar_documents, :ssp_document, foreign_key: true, null: true
  end
end
