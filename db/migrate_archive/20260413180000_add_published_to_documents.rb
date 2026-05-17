class AddPublishedToDocuments < ActiveRecord::Migration[8.0]
  def change
    # ProfileDocument and ControlCatalog already have published columns.
    # Add to the remaining document types.
    %i[ssp_documents sar_documents cdef_documents sap_documents poam_documents].each do |table|
      unless column_exists?(table, :published)
        add_column table, :published, :string
      end
    end
  end
end
