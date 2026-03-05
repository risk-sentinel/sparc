class CreateProfileDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :profile_documents do |t|
      t.string  :name,              null: false
      t.string  :file_type
      t.string  :status,            default: "pending"
      t.string  :original_filename
      t.text    :error_message
      t.string  :profile_type
      t.string  :profile_version
      t.string  :benchmark_id
      t.text    :description
      t.jsonb   :import_metadata,   default: {}

      t.timestamps
    end

    add_index :profile_documents, :status
    add_index :profile_documents, :created_at
    add_index :profile_documents, :profile_type

    create_table :profile_controls do |t|
      t.references :profile_document, null: false, foreign_key: { on_delete: :cascade }
      t.string  :control_id
      t.string  :title
      t.string  :severity
      t.string  :control_family
      t.string  :cci_references
      t.integer :row_order,  default: 0, null: false
      t.string  :group_id
      t.string  :rule_id

      t.timestamps
    end

    add_index :profile_controls, [:profile_document_id, :row_order],
              name: "idx_profile_controls_on_doc_row"
    add_index :profile_controls, [:profile_document_id, :control_family],
              name: "idx_profile_controls_on_doc_family"

    create_table :profile_control_fields do |t|
      t.references :profile_control, null: false, foreign_key: { on_delete: :cascade }
      t.string  :field_name,  null: false
      t.text    :field_value
      t.boolean :editable,    default: false

      t.timestamps
    end

    add_index :profile_control_fields, [:profile_control_id, :field_name],
              name: "idx_profile_fields_on_ctrl_name"
  end
end
