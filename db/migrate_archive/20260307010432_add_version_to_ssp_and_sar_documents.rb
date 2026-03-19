class AddVersionToSspAndSarDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :ssp_documents, :ssp_version, :string
    add_column :sar_documents, :sar_version, :string
  end
end
