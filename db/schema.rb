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

ActiveRecord::Schema[8.1].define(version: 2026_02_27_151230) do
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

  create_table "conversion_jobs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "document_id"
    t.string "document_type"
    t.text "error_message"
    t.string "job_type"
    t.string "status"
    t.datetime "updated_at", null: false
  end

  create_table "ssp_control_fields", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "editable", default: false
    t.string "field_name", null: false
    t.text "field_value"
    t.bigint "ssp_control_id", null: false
    t.datetime "updated_at", null: false
    t.index ["ssp_control_id", "field_name"], name: "index_ssp_control_fields_on_ssp_control_id_and_field_name"
    t.index ["ssp_control_id"], name: "index_ssp_control_fields_on_ssp_control_id"
  end

  create_table "ssp_controls", force: :cascade do |t|
    t.string "control_id", null: false
    t.datetime "created_at", null: false
    t.bigint "ssp_document_id", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["ssp_document_id", "control_id"], name: "index_ssp_controls_on_ssp_document_id_and_control_id", unique: true
    t.index ["ssp_document_id"], name: "index_ssp_controls_on_ssp_document_id"
  end

  create_table "ssp_documents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "file_type", null: false
    t.string "name", null: false
    t.string "original_filename"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_ssp_documents_on_created_at"
    t.index ["status"], name: "index_ssp_documents_on_status"
  end

  create_table "tpr_control_fields", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "editable"
    t.string "field_name"
    t.text "field_value"
    t.bigint "tpr_control_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tpr_control_id"], name: "index_tpr_control_fields_on_tpr_control_id"
  end

  create_table "tpr_controls", force: :cascade do |t|
    t.string "control_id"
    t.datetime "created_at", null: false
    t.string "title"
    t.bigint "tpr_document_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tpr_document_id"], name: "index_tpr_controls_on_tpr_document_id"
  end

  create_table "tpr_documents", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "file_type"
    t.string "name"
    t.string "original_filename"
    t.string "status"
    t.datetime "updated_at", null: false
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "ssp_control_fields", "ssp_controls"
  add_foreign_key "ssp_controls", "ssp_documents"
  add_foreign_key "tpr_control_fields", "tpr_controls"
  add_foreign_key "tpr_controls", "tpr_documents"
end
