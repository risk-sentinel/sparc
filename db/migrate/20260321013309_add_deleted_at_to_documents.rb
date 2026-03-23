class AddDeletedAtToDocuments < ActiveRecord::Migration[8.1]
  def change
    %i[ssp_documents sar_documents sap_documents poam_documents].each do |table|
      add_column table, :deleted_at, :datetime unless column_exists?(table, :deleted_at)
      add_index table, :deleted_at unless index_exists?(table, :deleted_at)
    end
  end
end
