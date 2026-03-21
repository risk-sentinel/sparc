class AddDeletedAtToDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :ssp_documents, :deleted_at, :datetime
    add_column :sar_documents, :deleted_at, :datetime
    add_column :sap_documents, :deleted_at, :datetime
    add_column :poam_documents, :deleted_at, :datetime

    add_index :ssp_documents, :deleted_at
    add_index :sar_documents, :deleted_at
    add_index :sap_documents, :deleted_at
    add_index :poam_documents, :deleted_at
  end
end
