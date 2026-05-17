class CreateOscalSchemas < ActiveRecord::Migration[8.0]
  def change
    create_table :oscal_schemas do |t|
      t.string  :oscal_version,       null: false
      t.string  :document_type,       null: false
      t.string  :schema_format,       null: false, default: "json"
      t.jsonb   :raw_schema,          null: false
      t.jsonb   :preprocessed_schema
      t.string  :root_key
      t.string  :source_url
      t.string  :checksum
      t.boolean :active,              null: false, default: true

      t.timestamps
    end

    add_index :oscal_schemas,
              [ :oscal_version, :document_type, :schema_format ],
              unique: true,
              name: "idx_oscal_schemas_version_type_format"
  end
end
