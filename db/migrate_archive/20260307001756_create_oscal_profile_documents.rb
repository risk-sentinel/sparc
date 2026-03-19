class CreateOscalProfileDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :profile_documents do |t|
      t.string  :name,               null: false
      t.string  :file_type
      t.string  :status,             default: "pending"
      t.string  :original_filename
      t.text    :error_message
      t.string  :baseline_level
      t.string  :profile_version
      t.string  :oscal_version
      t.text    :description
      t.jsonb   :import_metadata,    default: {}
      t.bigint  :control_catalog_id

      t.timestamps
    end

    add_index :profile_documents, :status
    add_index :profile_documents, :created_at
    add_index :profile_documents, :baseline_level
    add_foreign_key :profile_documents, :control_catalogs,
                    column: :control_catalog_id, on_delete: :nullify

    create_table :profile_controls do |t|
      t.references :profile_document, null: false, foreign_key: { on_delete: :cascade }
      t.string  :control_id
      t.string  :title
      t.string  :priority
      t.string  :control_family
      t.integer :row_order,    default: 0, null: false

      t.timestamps
    end

    add_index :profile_controls, %i[profile_document_id row_order],
              name: "idx_profile_controls_on_doc_row"
    add_index :profile_controls, %i[profile_document_id control_family],
              name: "idx_profile_controls_on_doc_family"
    add_index :profile_controls, %i[profile_document_id control_id],
              name: "idx_profile_controls_on_doc_ctrl", unique: true

    create_table :profile_control_fields do |t|
      t.references :profile_control, null: false, foreign_key: { on_delete: :cascade }
      t.string  :field_name,  null: false
      t.text    :field_value
      t.boolean :editable,    default: false

      t.timestamps
    end

    add_index :profile_control_fields, %i[profile_control_id field_name],
              name: "idx_profile_fields_on_ctrl_name"
  end
end
