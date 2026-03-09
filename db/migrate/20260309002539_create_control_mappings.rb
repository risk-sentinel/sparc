class CreateControlMappings < ActiveRecord::Migration[8.1]
  def change
    create_table :control_mappings do |t|
      t.string  :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string  :name, null: false
      t.text    :description
      t.string  :mapping_version, default: "1.0.0"
      t.string  :oscal_version, default: "1.2.1"
      t.string  :status, null: false, default: "draft"
      t.string  :method_type, default: "human"
      t.string  :matching_rationale, default: "semantic"
      t.references :source_catalog, null: false, foreign_key: { to_table: :control_catalogs }
      t.references :target_catalog, null: false, foreign_key: { to_table: :control_catalogs }
      t.jsonb :metadata_extra, default: {}
      t.timestamps
    end

    add_index :control_mappings, :uuid, unique: true
    add_index :control_mappings, :status
    add_index :control_mappings, [ :source_catalog_id, :target_catalog_id ]
  end
end
