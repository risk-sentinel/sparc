class AddResolvedCatalogJsonToProfileDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :profile_documents, :resolved_catalog_json, :jsonb, default: {}
  end
end
