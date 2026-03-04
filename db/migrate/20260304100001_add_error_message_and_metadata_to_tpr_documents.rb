class AddErrorMessageAndMetadataToTprDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :tpr_documents, :error_message, :text
    add_column :tpr_documents, :excel_metadata, :jsonb, default: {}
    add_index  :tpr_documents, :status
    add_index  :tpr_documents, :created_at
  end
end
