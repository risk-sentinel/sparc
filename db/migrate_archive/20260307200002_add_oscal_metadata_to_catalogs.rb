class AddOscalMetadataToCatalogs < ActiveRecord::Migration[8.1]
  def change
    change_table :control_catalogs do |t|
      t.string :oscal_version
      t.jsonb  :metadata_extra, default: {}, null: false
      t.string :published
    end

    add_column :profile_documents, :published, :string
  end
end
