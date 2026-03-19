class RenameTprToSar < ActiveRecord::Migration[8.1]
  def change
    # Rename tables: Test Plan Results → Security Assessment Results
    rename_table :tpr_documents, :sar_documents
    rename_table :tpr_controls, :sar_controls
    rename_table :tpr_control_fields, :sar_control_fields

    # Rename foreign key columns to match new table names
    rename_column :sar_controls, :tpr_document_id, :sar_document_id
    rename_column :sar_control_fields, :tpr_control_id, :sar_control_id
  end
end
