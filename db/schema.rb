# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_03_08_110000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "catalog_controls", force: :cascade do |t|
    t.string "baseline_impact"
    t.string "control_class"
    t.bigint "control_family_id", null: false
    t.string "control_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "guidance_data", default: {}
    t.jsonb "links_data", default: [], null: false
    t.jsonb "params_data", default: [], null: false
    t.jsonb "parts_data", default: [], null: false
    t.string "priority"
    t.jsonb "props_data", default: [], null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "uuid"
    t.index ["control_family_id", "control_id"], name: "index_catalog_controls_on_control_family_id_and_control_id", unique: true
    t.index ["control_family_id"], name: "index_catalog_controls_on_control_family_id"
    t.index ["control_id"], name: "index_catalog_controls_on_control_id"
  end

  create_table "cdef_control_fields", force: :cascade do |t|
    t.bigint "cdef_control_id", null: false
    t.datetime "created_at", null: false
    t.boolean "editable", default: false
    t.string "field_name", null: false
    t.text "field_value"
    t.datetime "updated_at", null: false
    t.index ["cdef_control_id", "field_name"], name: "idx_cdef_fields_on_ctrl_name"
    t.index ["cdef_control_id"], name: "index_cdef_control_fields_on_cdef_control_id"
  end

  create_table "cdef_controls", force: :cascade do |t|
    t.string "cci_references"
    t.bigint "cdef_document_id", null: false
    t.string "component_uuid"
    t.string "control_family"
    t.string "control_id"
    t.datetime "created_at", null: false
    t.string "group_id"
    t.jsonb "links_data", default: [], null: false
    t.jsonb "props_data", default: [], null: false
    t.jsonb "responsible_roles_data", default: [], null: false
    t.integer "row_order", default: 0, null: false
    t.string "rule_id"
    t.jsonb "set_parameters_data", default: [], null: false
    t.string "severity"
    t.jsonb "statements_data", default: {}, null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "uuid"
    t.index ["cdef_document_id", "control_family"], name: "idx_cdef_controls_on_doc_family"
    t.index ["cdef_document_id", "row_order"], name: "idx_cdef_controls_on_doc_row"
    t.index ["cdef_document_id"], name: "index_cdef_controls_on_cdef_document_id"
  end

  create_table "cdef_documents", force: :cascade do |t|
    t.jsonb "back_matter_data", default: [], null: false
    t.string "benchmark_id"
    t.string "cdef_type"
    t.string "cdef_version"
    t.jsonb "components_data", default: [], null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.text "error_message"
    t.string "file_type"
    t.jsonb "import_metadata", default: {}
    t.jsonb "metadata_extra", default: {}, null: false
    t.string "name", null: false
    t.string "original_filename"
    t.string "oscal_version"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.index ["cdef_type"], name: "index_cdef_documents_on_cdef_type"
    t.index ["created_at"], name: "index_cdef_documents_on_created_at"
    t.index ["status"], name: "index_cdef_documents_on_status"
  end

  create_table "control_catalogs", force: :cascade do |t|
    t.jsonb "back_matter_data", default: [], null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "metadata_extra", default: {}, null: false
    t.string "name", null: false
    t.string "oscal_version"
    t.string "source"
    t.datetime "updated_at", null: false
    t.string "uuid"
    t.string "version"
    t.index ["name"], name: "index_control_catalogs_on_name"
  end

  create_table "control_families", force: :cascade do |t|
    t.string "code", null: false
    t.bigint "control_catalog_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "links_data", default: [], null: false
    t.string "name", null: false
    t.jsonb "parts_data", default: [], null: false
    t.jsonb "props_data", default: [], null: false
    t.integer "sort_order", default: 0
    t.datetime "updated_at", null: false
    t.string "uuid"
    t.index ["code"], name: "index_control_families_on_code"
    t.index ["control_catalog_id", "code"], name: "index_control_families_on_control_catalog_id_and_code", unique: true
    t.index ["control_catalog_id"], name: "index_control_families_on_control_catalog_id"
  end

  create_table "conversion_jobs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "document_id"
    t.string "document_type"
    t.text "error_message"
    t.string "job_type"
    t.string "status"
    t.datetime "updated_at", null: false
  end

  create_table "poam_documents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "file_type"
    t.jsonb "import_metadata", default: {}
    t.jsonb "local_definitions_extra", default: {}
    t.jsonb "metadata_extra", default: {}
    t.string "name", null: false
    t.string "original_filename"
    t.string "oscal_version"
    t.string "poam_version"
    t.string "status", default: "pending"
    t.string "system_id"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_poam_documents_on_created_at"
    t.index ["status"], name: "index_poam_documents_on_status"
  end

  create_table "poam_finding_observations", force: :cascade do |t|
    t.bigint "poam_finding_id", null: false
    t.bigint "poam_observation_id", null: false
    t.index ["poam_finding_id", "poam_observation_id"], name: "idx_poam_finding_obs_unique", unique: true
    t.index ["poam_finding_id"], name: "index_poam_finding_observations_on_poam_finding_id"
    t.index ["poam_observation_id"], name: "index_poam_finding_observations_on_poam_observation_id"
  end

  create_table "poam_finding_risks", force: :cascade do |t|
    t.bigint "poam_finding_id", null: false
    t.bigint "poam_risk_id", null: false
    t.index ["poam_finding_id", "poam_risk_id"], name: "index_poam_finding_risks_on_poam_finding_id_and_poam_risk_id", unique: true
    t.index ["poam_finding_id"], name: "index_poam_finding_risks_on_poam_finding_id"
    t.index ["poam_risk_id"], name: "index_poam_finding_risks_on_poam_risk_id"
  end

  create_table "poam_findings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "implementation_statement_uuid"
    t.jsonb "links_data", default: []
    t.jsonb "origins_data", default: []
    t.bigint "poam_document_id", null: false
    t.jsonb "props_data", default: []
    t.text "remarks"
    t.jsonb "target_data", default: {}
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["poam_document_id", "uuid"], name: "index_poam_findings_on_poam_document_id_and_uuid", unique: true
    t.index ["poam_document_id"], name: "index_poam_findings_on_poam_document_id"
  end

  create_table "poam_item_findings", force: :cascade do |t|
    t.bigint "poam_finding_id", null: false
    t.bigint "poam_item_id", null: false
    t.index ["poam_finding_id"], name: "index_poam_item_findings_on_poam_finding_id"
    t.index ["poam_item_id", "poam_finding_id"], name: "index_poam_item_findings_on_poam_item_id_and_poam_finding_id", unique: true
    t.index ["poam_item_id"], name: "index_poam_item_findings_on_poam_item_id"
  end

  create_table "poam_item_observations", force: :cascade do |t|
    t.bigint "poam_item_id", null: false
    t.bigint "poam_observation_id", null: false
    t.index ["poam_item_id", "poam_observation_id"], name: "idx_poam_item_obs_unique", unique: true
    t.index ["poam_item_id"], name: "index_poam_item_observations_on_poam_item_id"
    t.index ["poam_observation_id"], name: "index_poam_item_observations_on_poam_observation_id"
  end

  create_table "poam_item_risks", force: :cascade do |t|
    t.bigint "poam_item_id", null: false
    t.bigint "poam_risk_id", null: false
    t.index ["poam_item_id", "poam_risk_id"], name: "index_poam_item_risks_on_poam_item_id_and_poam_risk_id", unique: true
    t.index ["poam_item_id"], name: "index_poam_item_risks_on_poam_item_id"
    t.index ["poam_risk_id"], name: "index_poam_item_risks_on_poam_risk_id"
  end

  create_table "poam_items", force: :cascade do |t|
    t.text "closure_evidence"
    t.datetime "created_at", null: false
    t.date "deadline"
    t.text "description"
    t.string "impact"
    t.text "internal_notes"
    t.string "likelihood"
    t.jsonb "links_data", default: []
    t.jsonb "origins_data", default: []
    t.bigint "poam_document_id", null: false
    t.string "poam_item_uuid"
    t.jsonb "props_data", default: []
    t.text "remarks"
    t.string "risk_level"
    t.string "risk_status"
    t.integer "row_order", default: 0, null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["poam_document_id", "risk_status"], name: "index_poam_items_on_poam_document_id_and_risk_status"
    t.index ["poam_document_id", "row_order"], name: "index_poam_items_on_poam_document_id_and_row_order"
    t.index ["poam_document_id"], name: "index_poam_items_on_poam_document_id"
  end

  create_table "poam_local_components", force: :cascade do |t|
    t.string "component_type"
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "links_data", default: []
    t.bigint "poam_document_id", null: false
    t.jsonb "props_data", default: []
    t.jsonb "protocols_data", default: []
    t.string "purpose"
    t.text "remarks"
    t.jsonb "responsible_roles_data", default: []
    t.text "status_remarks"
    t.string "status_state"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["poam_document_id", "uuid"], name: "index_poam_local_components_on_poam_document_id_and_uuid", unique: true
    t.index ["poam_document_id"], name: "index_poam_local_components_on_poam_document_id"
  end

  create_table "poam_milestones", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "dependencies_data", default: []
    t.text "description"
    t.date "due_date"
    t.jsonb "links_data", default: []
    t.string "milestone_type", default: "milestone"
    t.bigint "poam_remediation_id", null: false
    t.integer "position", default: 0
    t.jsonb "props_data", default: []
    t.text "remarks"
    t.jsonb "responsible_roles_data", default: []
    t.jsonb "subjects_data", default: []
    t.jsonb "timing_data", default: {}
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["poam_remediation_id", "uuid"], name: "index_poam_milestones_on_poam_remediation_id_and_uuid"
    t.index ["poam_remediation_id"], name: "index_poam_milestones_on_poam_remediation_id"
  end

  create_table "poam_observations", force: :cascade do |t|
    t.datetime "collected"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "expires"
    t.jsonb "links_data", default: []
    t.jsonb "methods_data", default: []
    t.jsonb "origins_data", default: []
    t.bigint "poam_document_id", null: false
    t.jsonb "props_data", default: []
    t.jsonb "relevant_evidence_data", default: []
    t.text "remarks"
    t.jsonb "subjects_data", default: []
    t.string "title"
    t.jsonb "types_data", default: []
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["poam_document_id", "uuid"], name: "index_poam_observations_on_poam_document_id_and_uuid", unique: true
    t.index ["poam_document_id"], name: "index_poam_observations_on_poam_document_id"
  end

  create_table "poam_remediations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "lifecycle"
    t.jsonb "links_data", default: []
    t.jsonb "origins_data", default: []
    t.bigint "poam_risk_id", null: false
    t.integer "position", default: 0
    t.jsonb "props_data", default: []
    t.text "remarks"
    t.jsonb "required_assets_data", default: []
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["poam_risk_id", "uuid"], name: "index_poam_remediations_on_poam_risk_id_and_uuid"
    t.index ["poam_risk_id"], name: "index_poam_remediations_on_poam_risk_id"
  end

  create_table "poam_risk_observations", force: :cascade do |t|
    t.bigint "poam_observation_id", null: false
    t.bigint "poam_risk_id", null: false
    t.index ["poam_observation_id"], name: "index_poam_risk_observations_on_poam_observation_id"
    t.index ["poam_risk_id", "poam_observation_id"], name: "idx_poam_risk_obs_unique", unique: true
    t.index ["poam_risk_id"], name: "index_poam_risk_observations_on_poam_risk_id"
  end

  create_table "poam_risks", force: :cascade do |t|
    t.jsonb "characterizations_data", default: []
    t.datetime "created_at", null: false
    t.datetime "deadline"
    t.text "description"
    t.string "impact"
    t.string "likelihood"
    t.jsonb "links_data", default: []
    t.jsonb "mitigating_factors_data", default: []
    t.jsonb "origins_data", default: []
    t.bigint "poam_document_id", null: false
    t.jsonb "props_data", default: []
    t.text "remarks"
    t.jsonb "risk_log_data", default: {}
    t.text "statement"
    t.string "status"
    t.jsonb "threat_ids_data", default: []
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["poam_document_id", "status"], name: "index_poam_risks_on_poam_document_id_and_status"
    t.index ["poam_document_id", "uuid"], name: "index_poam_risks_on_poam_document_id_and_uuid", unique: true
    t.index ["poam_document_id"], name: "index_poam_risks_on_poam_document_id"
  end

  create_table "profile_control_fields", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "editable", default: false
    t.string "field_name", null: false
    t.text "field_value"
    t.bigint "profile_control_id", null: false
    t.datetime "updated_at", null: false
    t.index ["profile_control_id", "field_name"], name: "idx_profile_fields_on_ctrl_name"
    t.index ["profile_control_id"], name: "index_profile_control_fields_on_profile_control_id"
  end

  create_table "profile_controls", force: :cascade do |t|
    t.jsonb "additions_data", default: [], null: false
    t.jsonb "alters_data", default: [], null: false
    t.string "control_family"
    t.string "control_id"
    t.datetime "created_at", null: false
    t.boolean "exclude", default: false, null: false
    t.string "priority"
    t.bigint "profile_document_id", null: false
    t.integer "row_order", default: 0, null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["profile_document_id", "control_family"], name: "idx_profile_controls_on_doc_family"
    t.index ["profile_document_id", "control_id"], name: "idx_profile_controls_on_doc_ctrl", unique: true
    t.index ["profile_document_id", "row_order"], name: "idx_profile_controls_on_doc_row"
    t.index ["profile_document_id"], name: "index_profile_controls_on_profile_document_id"
  end

  create_table "profile_documents", force: :cascade do |t|
    t.jsonb "back_matter_data", default: [], null: false
    t.string "baseline_level"
    t.bigint "control_catalog_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.text "error_message"
    t.string "file_type"
    t.jsonb "import_metadata", default: {}
    t.jsonb "metadata_extra", default: {}, null: false
    t.string "name", null: false
    t.string "original_filename"
    t.string "oscal_version"
    t.string "profile_version"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.index ["baseline_level"], name: "index_profile_documents_on_baseline_level"
    t.index ["created_at"], name: "index_profile_documents_on_created_at"
    t.index ["status"], name: "index_profile_documents_on_status"
  end

  create_table "sap_control_fields", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "editable", default: false
    t.string "field_name", null: false
    t.text "field_value"
    t.bigint "sap_control_id", null: false
    t.datetime "updated_at", null: false
    t.index ["sap_control_id", "field_name"], name: "idx_sap_fields_on_ctrl_name"
    t.index ["sap_control_id"], name: "index_sap_control_fields_on_sap_control_id"
  end

  create_table "sap_controls", force: :cascade do |t|
    t.string "assessment_method"
    t.string "assessment_status", default: "planned"
    t.string "assessor_name"
    t.string "control_family"
    t.string "control_id"
    t.datetime "created_at", null: false
    t.text "objective"
    t.integer "row_order", default: 0, null: false
    t.bigint "sap_document_id", null: false
    t.text "test_case"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["sap_document_id", "assessment_method"], name: "idx_sap_controls_on_doc_method"
    t.index ["sap_document_id", "control_family"], name: "idx_sap_controls_on_doc_family"
    t.index ["sap_document_id", "row_order"], name: "idx_sap_controls_on_doc_row"
    t.index ["sap_document_id"], name: "index_sap_controls_on_sap_document_id"
  end

  create_table "sap_documents", force: :cascade do |t|
    t.date "assessment_end"
    t.jsonb "assessment_scope", default: {}
    t.date "assessment_start"
    t.string "assessment_type", default: "initial"
    t.jsonb "assessors", default: []
    t.jsonb "back_matter_data", default: [], null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.text "error_message"
    t.string "file_type"
    t.jsonb "import_metadata", default: {}
    t.jsonb "metadata_extra", default: {}, null: false
    t.string "name", null: false
    t.string "original_filename"
    t.string "oscal_version"
    t.bigint "profile_document_id"
    t.string "sap_version"
    t.bigint "ssp_document_id"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_sap_documents_on_created_at"
    t.index ["profile_document_id"], name: "index_sap_documents_on_profile_document_id"
    t.index ["ssp_document_id"], name: "index_sap_documents_on_ssp_document_id"
    t.index ["status"], name: "index_sap_documents_on_status"
  end

  create_table "sar_control_fields", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "editable"
    t.string "field_name"
    t.text "field_value"
    t.bigint "sar_control_id", null: false
    t.datetime "updated_at", null: false
    t.index ["sar_control_id", "field_name"], name: "index_tpr_control_fields_on_control_id_and_field_name"
    t.index ["sar_control_id"], name: "index_sar_control_fields_on_sar_control_id"
  end

  create_table "sar_controls", force: :cascade do |t|
    t.string "cached_result"
    t.string "control_family"
    t.string "control_id"
    t.datetime "created_at", null: false
    t.integer "row_order", default: 0, null: false
    t.bigint "sar_document_id", null: false
    t.string "section"
    t.string "subject_asset"
    t.string "subject_environment"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["sar_document_id", "cached_result"], name: "index_sar_controls_on_sar_document_id_and_cached_result"
    t.index ["sar_document_id", "control_family"], name: "index_sar_controls_on_sar_document_id_and_control_family"
    t.index ["sar_document_id", "row_order"], name: "index_sar_controls_on_sar_document_id_and_row_order"
    t.index ["sar_document_id"], name: "index_sar_controls_on_sar_document_id"
    t.index ["section"], name: "index_sar_controls_on_section"
  end

  create_table "sar_documents", force: :cascade do |t|
    t.datetime "assessment_end"
    t.jsonb "assessment_log_data", default: []
    t.datetime "assessment_start"
    t.jsonb "attestations_data", default: [], null: false
    t.jsonb "back_matter_data", default: [], null: false
    t.datetime "created_at", null: false
    t.string "creation_method", default: "excel"
    t.text "description"
    t.text "error_message"
    t.jsonb "excel_metadata", default: {}
    t.string "file_type"
    t.string "import_ap_href"
    t.jsonb "import_metadata", default: {}
    t.jsonb "local_definitions_extra", default: {}
    t.jsonb "metadata_extra", default: {}
    t.string "name"
    t.string "original_filename"
    t.string "oscal_version"
    t.jsonb "reviewed_controls_data", default: {}
    t.bigint "sap_document_id"
    t.string "sar_version"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_sar_documents_on_created_at"
    t.index ["sap_document_id"], name: "index_sar_documents_on_sap_document_id"
    t.index ["status"], name: "index_sar_documents_on_status"
  end

  create_table "sar_finding_observations", force: :cascade do |t|
    t.bigint "sar_finding_id", null: false
    t.bigint "sar_observation_id", null: false
    t.index ["sar_finding_id", "sar_observation_id"], name: "idx_sar_finding_obs_unique", unique: true
    t.index ["sar_finding_id"], name: "index_sar_finding_observations_on_sar_finding_id"
    t.index ["sar_observation_id"], name: "index_sar_finding_observations_on_sar_observation_id"
  end

  create_table "sar_finding_risks", force: :cascade do |t|
    t.bigint "sar_finding_id", null: false
    t.bigint "sar_risk_id", null: false
    t.index ["sar_finding_id", "sar_risk_id"], name: "idx_sar_finding_risk_unique", unique: true
    t.index ["sar_finding_id"], name: "index_sar_finding_risks_on_sar_finding_id"
    t.index ["sar_risk_id"], name: "index_sar_finding_risks_on_sar_risk_id"
  end

  create_table "sar_findings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "implementation_statement_uuid"
    t.jsonb "links_data", default: []
    t.jsonb "origins_data", default: []
    t.jsonb "props_data", default: []
    t.text "remarks"
    t.bigint "sar_result_id", null: false
    t.jsonb "target_data", default: {}
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["sar_result_id", "uuid"], name: "idx_sar_findings_result_uuid", unique: true
    t.index ["sar_result_id"], name: "index_sar_findings_on_sar_result_id"
  end

  create_table "sar_local_components", force: :cascade do |t|
    t.string "component_type"
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "links_data", default: []
    t.jsonb "props_data", default: []
    t.jsonb "protocols_data", default: []
    t.string "purpose"
    t.text "remarks"
    t.jsonb "responsible_roles_data", default: []
    t.bigint "sar_document_id", null: false
    t.text "status_remarks"
    t.string "status_state"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["sar_document_id", "uuid"], name: "idx_sar_local_comp_doc_uuid", unique: true
    t.index ["sar_document_id"], name: "index_sar_local_components_on_sar_document_id"
  end

  create_table "sar_observations", force: :cascade do |t|
    t.datetime "collected"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "expires"
    t.jsonb "links_data", default: []
    t.jsonb "methods_data", default: []
    t.jsonb "origins_data", default: []
    t.jsonb "props_data", default: []
    t.jsonb "relevant_evidence_data", default: []
    t.text "remarks"
    t.bigint "sar_result_id", null: false
    t.jsonb "subjects_data", default: []
    t.string "title"
    t.jsonb "types_data", default: []
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["sar_result_id", "uuid"], name: "idx_sar_obs_result_uuid", unique: true
    t.index ["sar_result_id"], name: "index_sar_observations_on_sar_result_id"
  end

  create_table "sar_results", force: :cascade do |t|
    t.jsonb "assessment_log_data", default: []
    t.jsonb "attestations_data", default: []
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "end_time"
    t.jsonb "links_data", default: []
    t.jsonb "local_definitions_data", default: {}, null: false
    t.integer "position", default: 0
    t.jsonb "props_data", default: []
    t.text "remarks"
    t.jsonb "reviewed_controls_data", default: {}
    t.bigint "sar_document_id", null: false
    t.datetime "start_time", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["sar_document_id", "uuid"], name: "idx_sar_results_doc_uuid", unique: true
    t.index ["sar_document_id"], name: "index_sar_results_on_sar_document_id"
  end

  create_table "sar_risk_observations", force: :cascade do |t|
    t.bigint "sar_observation_id", null: false
    t.bigint "sar_risk_id", null: false
    t.index ["sar_observation_id"], name: "index_sar_risk_observations_on_sar_observation_id"
    t.index ["sar_risk_id", "sar_observation_id"], name: "idx_sar_risk_obs_unique", unique: true
    t.index ["sar_risk_id"], name: "index_sar_risk_observations_on_sar_risk_id"
  end

  create_table "sar_risks", force: :cascade do |t|
    t.jsonb "characterizations_data", default: []
    t.datetime "created_at", null: false
    t.datetime "deadline"
    t.text "description"
    t.string "impact"
    t.string "likelihood"
    t.jsonb "links_data", default: []
    t.jsonb "mitigating_factors_data", default: []
    t.jsonb "origins_data", default: []
    t.jsonb "props_data", default: []
    t.text "remarks"
    t.jsonb "remediations_data", default: []
    t.jsonb "risk_log_data", default: {}
    t.bigint "sar_result_id", null: false
    t.text "statement"
    t.string "status"
    t.jsonb "threat_ids_data", default: []
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["sar_result_id", "status"], name: "idx_sar_risks_result_status"
    t.index ["sar_result_id", "uuid"], name: "idx_sar_risks_result_uuid", unique: true
    t.index ["sar_result_id"], name: "index_sar_risks_on_sar_result_id"
  end

  create_table "ssp_by_components", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "export_data", default: {}
    t.string "implementation_status"
    t.jsonb "inherited_data", default: []
    t.jsonb "links_data", default: []
    t.jsonb "props_data", default: []
    t.text "remarks"
    t.jsonb "responsible_roles_data", default: []
    t.jsonb "satisfied_data", default: []
    t.jsonb "set_parameters_data", default: []
    t.bigint "ssp_component_id", null: false
    t.bigint "ssp_control_id", null: false
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["ssp_component_id"], name: "index_ssp_by_components_on_ssp_component_id"
    t.index ["ssp_control_id", "ssp_component_id"], name: "idx_ssp_by_comp_ctrl_comp", unique: true
    t.index ["ssp_control_id"], name: "index_ssp_by_components_on_ssp_control_id"
  end

  create_table "ssp_components", force: :cascade do |t|
    t.bigint "cdef_document_id"
    t.string "component_type", null: false
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.jsonb "links_data", default: []
    t.jsonb "props_data", default: []
    t.jsonb "protocols_data", default: []
    t.string "purpose"
    t.text "remarks"
    t.jsonb "responsible_roles_data", default: []
    t.bigint "ssp_document_id", null: false
    t.text "status_remarks"
    t.string "status_state", default: "operational"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["cdef_document_id"], name: "index_ssp_components_on_cdef_document_id"
    t.index ["ssp_document_id", "component_type"], name: "idx_ssp_components_doc_type"
    t.index ["ssp_document_id", "uuid"], name: "idx_ssp_components_doc_uuid", unique: true
    t.index ["ssp_document_id"], name: "index_ssp_components_on_ssp_document_id"
  end

  create_table "ssp_control_fields", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "editable"
    t.string "field_name"
    t.text "field_value"
    t.bigint "ssp_control_id", null: false
    t.datetime "updated_at", null: false
    t.index ["ssp_control_id"], name: "index_ssp_control_fields_on_ssp_control_id"
  end

  create_table "ssp_controls", force: :cascade do |t|
    t.string "control_id"
    t.datetime "created_at", null: false
    t.bigint "parent_id"
    t.integer "row_order", default: 0, null: false
    t.bigint "ssp_document_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["parent_id"], name: "index_ssp_controls_on_parent_id"
    t.index ["ssp_document_id", "row_order"], name: "index_ssp_controls_on_ssp_document_id_and_row_order"
    t.index ["ssp_document_id"], name: "index_ssp_controls_on_ssp_document_id"
  end

  create_table "ssp_document_cdef_documents", force: :cascade do |t|
    t.bigint "cdef_document_id", null: false
    t.bigint "ssp_document_id", null: false
    t.index ["cdef_document_id"], name: "index_ssp_document_cdef_documents_on_cdef_document_id"
    t.index ["ssp_document_id", "cdef_document_id"], name: "idx_ssp_cdef_unique", unique: true
    t.index ["ssp_document_id"], name: "index_ssp_document_cdef_documents_on_ssp_document_id"
  end

  create_table "ssp_documents", force: :cascade do |t|
    t.text "authorization_boundary_description"
    t.datetime "created_at", null: false
    t.string "creation_method", default: "excel"
    t.text "data_flow_description"
    t.date "date_authorized"
    t.text "description"
    t.text "error_message"
    t.string "file_type"
    t.jsonb "import_metadata", default: {}
    t.string "import_profile_href"
    t.jsonb "metadata_extra", default: {}
    t.string "name"
    t.text "network_architecture_description"
    t.string "original_filename"
    t.string "oscal_version"
    t.bigint "profile_document_id"
    t.string "security_objective_availability"
    t.string "security_objective_confidentiality"
    t.string "security_objective_integrity"
    t.string "security_sensitivity_level"
    t.string "ssp_version"
    t.string "status"
    t.string "system_id"
    t.string "system_name_short"
    t.string "system_status", default: "operational"
    t.datetime "updated_at", null: false
    t.index ["profile_document_id"], name: "index_ssp_documents_on_profile_document_id"
  end

  create_table "ssp_information_types", force: :cascade do |t|
    t.text "availability_impact_adjustment"
    t.string "availability_impact_base"
    t.string "availability_impact_selected"
    t.jsonb "categorizations_data", default: []
    t.text "confidentiality_impact_adjustment"
    t.string "confidentiality_impact_base"
    t.string "confidentiality_impact_selected"
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.text "integrity_impact_adjustment"
    t.string "integrity_impact_base"
    t.string "integrity_impact_selected"
    t.jsonb "links_data", default: []
    t.jsonb "props_data", default: []
    t.bigint "ssp_document_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["ssp_document_id", "uuid"], name: "idx_ssp_info_types_doc_uuid", unique: true
    t.index ["ssp_document_id"], name: "index_ssp_information_types_on_ssp_document_id"
  end

  create_table "ssp_inventory_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description", null: false
    t.jsonb "implemented_components_data", default: []
    t.jsonb "links_data", default: []
    t.jsonb "props_data", default: []
    t.text "remarks"
    t.jsonb "responsible_parties_data", default: []
    t.bigint "ssp_document_id", null: false
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["ssp_document_id", "uuid"], name: "idx_ssp_inv_items_doc_uuid", unique: true
    t.index ["ssp_document_id"], name: "index_ssp_inventory_items_on_ssp_document_id"
  end

  create_table "ssp_leveraged_authorizations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date_authorized", null: false
    t.jsonb "links_data", default: []
    t.string "party_uuid", null: false
    t.jsonb "props_data", default: []
    t.text "remarks"
    t.bigint "ssp_document_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["ssp_document_id", "uuid"], name: "idx_ssp_lev_auths_doc_uuid", unique: true
    t.index ["ssp_document_id"], name: "index_ssp_leveraged_authorizations_on_ssp_document_id"
  end

  create_table "ssp_users", force: :cascade do |t|
    t.jsonb "authorized_privileges_data", default: []
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "links_data", default: []
    t.jsonb "props_data", default: []
    t.text "remarks"
    t.jsonb "role_ids_data", default: []
    t.string "short_name"
    t.bigint "ssp_document_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "uuid", null: false
    t.index ["ssp_document_id", "uuid"], name: "idx_ssp_users_doc_uuid", unique: true
    t.index ["ssp_document_id"], name: "index_ssp_users_on_ssp_document_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "catalog_controls", "control_families"
  add_foreign_key "cdef_control_fields", "cdef_controls", on_delete: :cascade
  add_foreign_key "cdef_controls", "cdef_documents", on_delete: :cascade
  add_foreign_key "control_families", "control_catalogs"
  add_foreign_key "poam_finding_observations", "poam_findings", on_delete: :cascade
  add_foreign_key "poam_finding_observations", "poam_observations", on_delete: :cascade
  add_foreign_key "poam_finding_risks", "poam_findings", on_delete: :cascade
  add_foreign_key "poam_finding_risks", "poam_risks", on_delete: :cascade
  add_foreign_key "poam_findings", "poam_documents", on_delete: :cascade
  add_foreign_key "poam_item_findings", "poam_findings", on_delete: :cascade
  add_foreign_key "poam_item_findings", "poam_items", on_delete: :cascade
  add_foreign_key "poam_item_observations", "poam_items", on_delete: :cascade
  add_foreign_key "poam_item_observations", "poam_observations", on_delete: :cascade
  add_foreign_key "poam_item_risks", "poam_items", on_delete: :cascade
  add_foreign_key "poam_item_risks", "poam_risks", on_delete: :cascade
  add_foreign_key "poam_items", "poam_documents", on_delete: :cascade
  add_foreign_key "poam_local_components", "poam_documents", on_delete: :cascade
  add_foreign_key "poam_milestones", "poam_remediations", on_delete: :cascade
  add_foreign_key "poam_observations", "poam_documents", on_delete: :cascade
  add_foreign_key "poam_remediations", "poam_risks", on_delete: :cascade
  add_foreign_key "poam_risk_observations", "poam_observations", on_delete: :cascade
  add_foreign_key "poam_risk_observations", "poam_risks", on_delete: :cascade
  add_foreign_key "poam_risks", "poam_documents", on_delete: :cascade
  add_foreign_key "profile_control_fields", "profile_controls", on_delete: :cascade
  add_foreign_key "profile_controls", "profile_documents", on_delete: :cascade
  add_foreign_key "profile_documents", "control_catalogs", on_delete: :nullify
  add_foreign_key "sap_control_fields", "sap_controls", on_delete: :cascade
  add_foreign_key "sap_controls", "sap_documents", on_delete: :cascade
  add_foreign_key "sap_documents", "profile_documents", on_delete: :nullify
  add_foreign_key "sap_documents", "ssp_documents", on_delete: :nullify
  add_foreign_key "sar_control_fields", "sar_controls", on_delete: :cascade
  add_foreign_key "sar_controls", "sar_documents", on_delete: :cascade
  add_foreign_key "sar_documents", "sap_documents", on_delete: :nullify
  add_foreign_key "sar_finding_observations", "sar_findings", on_delete: :cascade
  add_foreign_key "sar_finding_observations", "sar_observations", on_delete: :cascade
  add_foreign_key "sar_finding_risks", "sar_findings", on_delete: :cascade
  add_foreign_key "sar_finding_risks", "sar_risks", on_delete: :cascade
  add_foreign_key "sar_findings", "sar_results", on_delete: :cascade
  add_foreign_key "sar_local_components", "sar_documents", on_delete: :cascade
  add_foreign_key "sar_observations", "sar_results", on_delete: :cascade
  add_foreign_key "sar_results", "sar_documents", on_delete: :cascade
  add_foreign_key "sar_risk_observations", "sar_observations", on_delete: :cascade
  add_foreign_key "sar_risk_observations", "sar_risks", on_delete: :cascade
  add_foreign_key "sar_risks", "sar_results", on_delete: :cascade
  add_foreign_key "ssp_by_components", "ssp_components", on_delete: :cascade
  add_foreign_key "ssp_by_components", "ssp_controls", on_delete: :cascade
  add_foreign_key "ssp_components", "cdef_documents", on_delete: :nullify
  add_foreign_key "ssp_components", "ssp_documents", on_delete: :cascade
  add_foreign_key "ssp_control_fields", "ssp_controls"
  add_foreign_key "ssp_controls", "ssp_controls", column: "parent_id"
  add_foreign_key "ssp_controls", "ssp_documents"
  add_foreign_key "ssp_document_cdef_documents", "cdef_documents", on_delete: :cascade
  add_foreign_key "ssp_document_cdef_documents", "ssp_documents", on_delete: :cascade
  add_foreign_key "ssp_documents", "profile_documents", on_delete: :nullify
  add_foreign_key "ssp_information_types", "ssp_documents", on_delete: :cascade
  add_foreign_key "ssp_inventory_items", "ssp_documents", on_delete: :cascade
  add_foreign_key "ssp_leveraged_authorizations", "ssp_documents", on_delete: :cascade
  add_foreign_key "ssp_users", "ssp_documents", on_delete: :cascade
end
