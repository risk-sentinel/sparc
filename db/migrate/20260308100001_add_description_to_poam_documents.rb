class AddDescriptionToPoamDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :poam_documents, :description, :text
  end
end
