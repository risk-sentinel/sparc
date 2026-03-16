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
        # Backfill: use metadata_extra catalog_uuid for the first row per value,
        # generate fresh UUIDs for duplicates or rows without a catalog_uuid.
        execute <<~SQL
          WITH ranked AS (
            SELECT id,
                   metadata_extra->>'catalog_uuid' AS cat_uuid,
                   ROW_NUMBER() OVER (
                     PARTITION BY metadata_extra->>'catalog_uuid'
                     ORDER BY id
                   ) AS rn
            FROM control_catalogs
          )
          UPDATE control_catalogs c
          SET oscal_uuid = CASE
            WHEN r.cat_uuid IS NOT NULL AND r.rn = 1
              THEN r.cat_uuid
            ELSE gen_random_uuid()::text
          END
          FROM ranked r
          WHERE c.id = r.id
        SQL
        change_column_null :control_catalogs, :oscal_uuid, false
      end
    end
  end
end
