class AddProfileLineageAndCatalogOscalUuid < ActiveRecord::Migration[8.1]
  def change
    # Self-referencing FK for profile-from-profile tailoring lineage
    add_reference :profile_documents, :source_profile,
                  foreign_key: { to_table: :profile_documents }, null: true

    # Dedicated column for the OSCAL catalog UUID (previously only in metadata_extra)
    add_column :control_catalogs, :oscal_uuid, :string
    add_index :control_catalogs, :oscal_uuid, unique: true

    reversible do |dir|
      dir.up do
        # Backfill from metadata_extra where available, otherwise generate new UUIDs
        execute <<~SQL
          UPDATE control_catalogs
          SET oscal_uuid = COALESCE(
            metadata_extra->>'catalog_uuid',
            gen_random_uuid()::text
          )
        SQL
        change_column_null :control_catalogs, :oscal_uuid, false
      end
    end
  end
end
