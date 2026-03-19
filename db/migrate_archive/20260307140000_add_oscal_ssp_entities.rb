class AddOscalSspEntities < ActiveRecord::Migration[8.0]
  def change
    # ── A. Expand ssp_documents with OSCAL system-characteristics fields ──
    change_table :ssp_documents, bulk: true do |t|
      t.string  :creation_method, default: "excel"
      # error_message already exists from create_ssp_documents migration
      t.string  :oscal_version
      t.string  :system_id
      t.text    :description
      t.string  :system_name_short
      t.string  :security_sensitivity_level
      t.string  :security_objective_confidentiality
      t.string  :security_objective_integrity
      t.string  :security_objective_availability
      t.string  :system_status, default: "operational"
      t.date    :date_authorized
      t.text    :authorization_boundary_description
      t.text    :network_architecture_description
      t.text    :data_flow_description
      t.string  :import_profile_href
      t.jsonb   :metadata_extra, default: {}
      t.jsonb   :import_metadata, default: {}
    end

    add_reference :ssp_documents, :profile_document,
                  foreign_key: { on_delete: :nullify }, null: true

    # ── B. ssp_information_types ──
    create_table :ssp_information_types do |t|
      t.references :ssp_document, null: false, foreign_key: { on_delete: :cascade }
      t.string  :uuid, null: false
      t.string  :title, null: false
      t.text    :description, null: false
      t.string  :confidentiality_impact_base
      t.string  :confidentiality_impact_selected
      t.text    :confidentiality_impact_adjustment
      t.string  :integrity_impact_base
      t.string  :integrity_impact_selected
      t.text    :integrity_impact_adjustment
      t.string  :availability_impact_base
      t.string  :availability_impact_selected
      t.text    :availability_impact_adjustment
      t.jsonb   :categorizations_data, default: []
      t.jsonb   :props_data, default: []
      t.jsonb   :links_data, default: []
      t.timestamps
    end
    add_index :ssp_information_types, %i[ssp_document_id uuid],
              unique: true, name: "idx_ssp_info_types_doc_uuid"

    # ── C. ssp_components ──
    create_table :ssp_components do |t|
      t.references :ssp_document, null: false, foreign_key: { on_delete: :cascade }
      t.string  :uuid, null: false
      t.string  :component_type, null: false
      t.string  :title, null: false
      t.text    :description, null: false
      t.string  :purpose
      t.string  :status_state, default: "operational"
      t.text    :status_remarks
      t.references :cdef_document, foreign_key: { on_delete: :nullify }, null: true
      t.jsonb   :responsible_roles_data, default: []
      t.jsonb   :protocols_data, default: []
      t.jsonb   :props_data, default: []
      t.jsonb   :links_data, default: []
      t.text    :remarks
      t.timestamps
    end
    add_index :ssp_components, %i[ssp_document_id uuid],
              unique: true, name: "idx_ssp_components_doc_uuid"
    add_index :ssp_components, %i[ssp_document_id component_type],
              name: "idx_ssp_components_doc_type"

    # ── D. ssp_users ──
    create_table :ssp_users do |t|
      t.references :ssp_document, null: false, foreign_key: { on_delete: :cascade }
      t.string  :uuid, null: false
      t.string  :title
      t.text    :description
      t.string  :short_name
      t.jsonb   :role_ids_data, default: []
      t.jsonb   :authorized_privileges_data, default: []
      t.jsonb   :props_data, default: []
      t.jsonb   :links_data, default: []
      t.text    :remarks
      t.timestamps
    end
    add_index :ssp_users, %i[ssp_document_id uuid],
              unique: true, name: "idx_ssp_users_doc_uuid"

    # ── E. ssp_leveraged_authorizations ──
    create_table :ssp_leveraged_authorizations do |t|
      t.references :ssp_document, null: false, foreign_key: { on_delete: :cascade }
      t.string  :uuid, null: false
      t.string  :title, null: false
      t.string  :party_uuid, null: false
      t.date    :date_authorized, null: false
      t.jsonb   :props_data, default: []
      t.jsonb   :links_data, default: []
      t.text    :remarks
      t.timestamps
    end
    add_index :ssp_leveraged_authorizations, %i[ssp_document_id uuid],
              unique: true, name: "idx_ssp_lev_auths_doc_uuid"

    # ── F. ssp_inventory_items ──
    create_table :ssp_inventory_items do |t|
      t.references :ssp_document, null: false, foreign_key: { on_delete: :cascade }
      t.string  :uuid, null: false
      t.text    :description, null: false
      t.jsonb   :implemented_components_data, default: []
      t.jsonb   :responsible_parties_data, default: []
      t.jsonb   :props_data, default: []
      t.jsonb   :links_data, default: []
      t.text    :remarks
      t.timestamps
    end
    add_index :ssp_inventory_items, %i[ssp_document_id uuid],
              unique: true, name: "idx_ssp_inv_items_doc_uuid"

    # ── G. ssp_by_components (control ↔ component join) ──
    create_table :ssp_by_components do |t|
      t.references :ssp_control, null: false, foreign_key: { on_delete: :cascade }
      t.references :ssp_component, null: false, foreign_key: { on_delete: :cascade }
      t.string  :uuid, null: false
      t.text    :description
      t.string  :implementation_status
      t.jsonb   :export_data, default: {}
      t.jsonb   :inherited_data, default: []
      t.jsonb   :satisfied_data, default: []
      t.jsonb   :responsible_roles_data, default: []
      t.jsonb   :set_parameters_data, default: []
      t.jsonb   :props_data, default: []
      t.jsonb   :links_data, default: []
      t.text    :remarks
      t.timestamps
    end
    add_index :ssp_by_components, %i[ssp_control_id ssp_component_id],
              unique: true, name: "idx_ssp_by_comp_ctrl_comp"

    # ── H. ssp_document_cdef_documents (SSP ↔ CDEF join) ──
    create_table :ssp_document_cdef_documents do |t|
      t.references :ssp_document, null: false, foreign_key: { on_delete: :cascade }
      t.references :cdef_document, null: false, foreign_key: { on_delete: :cascade }
    end
    add_index :ssp_document_cdef_documents, %i[ssp_document_id cdef_document_id],
              unique: true, name: "idx_ssp_cdef_unique"
  end
end
