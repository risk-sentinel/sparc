class CreateSapDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :sap_documents do |t|
      t.string :name, null: false
      t.string :file_type
      t.string :original_filename
      t.string :status, default: "pending"
      t.text :error_message
      t.string :sap_version
      t.string :oscal_version
      t.text :description
      t.jsonb :import_metadata, default: {}

      # References to source documents
      t.references :ssp_document, foreign_key: { on_delete: :nullify }
      t.references :profile_document, foreign_key: { on_delete: :nullify }

      # Assessment plan metadata
      t.string :assessment_type, default: "initial"
      t.date :assessment_start
      t.date :assessment_end
      t.jsonb :assessors, default: []
      t.jsonb :assessment_scope, default: {}

      t.timestamps
    end

    add_index :sap_documents, :status
    add_index :sap_documents, :created_at

    create_table :sap_controls do |t|
      t.references :sap_document, null: false, foreign_key: { on_delete: :cascade }
      t.string :control_id
      t.string :title
      t.string :control_family
      t.integer :row_order, default: 0, null: false

      # Assessment-specific attributes
      t.string :assessment_method  # examine, interview, test
      t.string :assessment_status, default: "planned"  # planned, in-progress, completed
      t.string :assessor_name
      t.text :objective
      t.text :test_case

      t.timestamps
    end

    add_index :sap_controls, [:sap_document_id, :control_family], name: "idx_sap_controls_on_doc_family"
    add_index :sap_controls, [:sap_document_id, :row_order], name: "idx_sap_controls_on_doc_row"
    add_index :sap_controls, [:sap_document_id, :assessment_method], name: "idx_sap_controls_on_doc_method"

    create_table :sap_control_fields do |t|
      t.references :sap_control, null: false, foreign_key: { on_delete: :cascade }
      t.string :field_name, null: false
      t.text :field_value
      t.boolean :editable, default: false

      t.timestamps
    end

    add_index :sap_control_fields, [:sap_control_id, :field_name], name: "idx_sap_fields_on_ctrl_name"
  end
end
