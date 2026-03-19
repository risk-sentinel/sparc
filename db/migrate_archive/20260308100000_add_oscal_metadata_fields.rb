class AddOscalMetadataFields < ActiveRecord::Migration[8.1]
  def change
    # SAP: add metadata_extra for preserving OSCAL metadata (roles, parties, revisions, etc.)
    add_column :sap_documents, :metadata_extra, :jsonb, default: {}, null: false

    # CDEF: add metadata_extra and oscal_version (both missing)
    add_column :cdef_documents, :metadata_extra, :jsonb, default: {}, null: false
    add_column :cdef_documents, :oscal_version, :string

    # Profile: add metadata_extra for preserving OSCAL metadata
    add_column :profile_documents, :metadata_extra, :jsonb, default: {}, null: false
  end
end
