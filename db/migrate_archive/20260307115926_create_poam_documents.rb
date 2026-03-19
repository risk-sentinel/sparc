class CreatePoamDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :poam_documents do |t|
      t.string  :name, null: false
      t.string  :file_type
      t.string  :original_filename
      t.string  :status, default: "pending"
      t.text    :error_message
      t.string  :poam_version
      t.string  :oscal_version
      t.string  :system_id
      t.jsonb   :import_metadata, default: {}
      t.jsonb   :observations_data, default: []
      t.jsonb   :risks_data, default: []
      t.timestamps
    end
    add_index :poam_documents, :status
    add_index :poam_documents, :created_at

    create_table :poam_items do |t|
      t.references :poam_document, null: false, foreign_key: { on_delete: :cascade }
      t.string  :title
      t.text    :description
      t.string  :poam_item_uuid
      t.string  :risk_status
      t.string  :risk_level
      t.string  :likelihood
      t.string  :impact
      t.date    :deadline
      t.string  :related_risk_uuid
      t.string  :related_observation_uuid
      t.integer :row_order, default: 0, null: false
      t.timestamps
    end
    add_index :poam_items, [ :poam_document_id, :row_order ]
    add_index :poam_items, [ :poam_document_id, :risk_status ]

    create_table :poam_item_fields do |t|
      t.references :poam_item, null: false, foreign_key: { on_delete: :cascade }
      t.string  :field_name, null: false
      t.text    :field_value
      t.boolean :editable, default: false
      t.timestamps
    end
    add_index :poam_item_fields, [ :poam_item_id, :field_name ]
  end
end
