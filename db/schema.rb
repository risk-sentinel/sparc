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

ActiveRecord::Schema[8.1].define(version: 2026_03_06_221831) do
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
    t.bigint "control_family_id", null: false
    t.string "control_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.jsonb "guidance_data", default: {}
    t.string "priority"
    t.string "title"
    t.datetime "updated_at", null: false
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
    t.string "control_family"
    t.string "control_id"
    t.datetime "created_at", null: false
    t.string "group_id"
    t.integer "row_order", default: 0, null: false
    t.string "rule_id"
    t.string "severity"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["cdef_document_id", "control_family"], name: "idx_cdef_controls_on_doc_family"
    t.index ["cdef_document_id", "row_order"], name: "idx_cdef_controls_on_doc_row"
    t.index ["cdef_document_id"], name: "index_cdef_controls_on_cdef_document_id"
  end

  create_table "cdef_documents", force: :cascade do |t|
    t.string "benchmark_id"
    t.string "cdef_type"
    t.string "cdef_version"
    t.datetime "created_at", null: false
    t.text "description"
    t.text "error_message"
    t.string "file_type"
    t.jsonb "import_metadata", default: {}
    t.string "name", null: false
    t.string "original_filename"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.index ["cdef_type"], name: "index_cdef_documents_on_cdef_type"
    t.index ["created_at"], name: "index_cdef_documents_on_created_at"
    t.index ["status"], name: "index_cdef_documents_on_status"
  end

  create_table "control_catalogs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.string "source"
    t.datetime "updated_at", null: false
    t.string "version"
    t.index ["name"], name: "index_control_catalogs_on_name"
  end

  create_table "control_families", force: :cascade do |t|
    t.string "code", null: false
    t.bigint "control_catalog_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.integer "sort_order", default: 0
    t.datetime "updated_at", null: false
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
    t.datetime "created_at", null: false
    t.text "error_message"
    t.jsonb "excel_metadata", default: {}
    t.string "file_type"
    t.string "name"
    t.string "original_filename"
    t.string "status"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_sar_documents_on_created_at"
    t.index ["status"], name: "index_sar_documents_on_status"
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

  create_table "ssp_documents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "file_type"
    t.string "name"
    t.string "original_filename"
    t.string "status"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "catalog_controls", "control_families"
  add_foreign_key "cdef_control_fields", "cdef_controls", on_delete: :cascade
  add_foreign_key "cdef_controls", "cdef_documents", on_delete: :cascade
  add_foreign_key "control_families", "control_catalogs"
  add_foreign_key "sar_control_fields", "sar_controls", on_delete: :cascade
  add_foreign_key "sar_controls", "sar_documents", on_delete: :cascade
  add_foreign_key "ssp_control_fields", "ssp_controls"
  add_foreign_key "ssp_controls", "ssp_controls", column: "parent_id"
  add_foreign_key "ssp_controls", "ssp_documents"
end
