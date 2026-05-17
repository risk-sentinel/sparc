# Adds first-class statement records to SSP and CDEF (consumer
# implementation responses) and read-only catalog parts (the policy
# language source-of-truth). Backfill walks existing documents'
# linked profile resolved_catalog_json via CatalogPartExtractorService.
#
# UUID stability invariant (#397 forward-compat contract): backfilled
# rows use OscalUuidService.derived(parent_control.uuid,
# "ssp-statement"/"cdef-statement", statement_id) so previously-exported
# documents round-trip with byte-identical statement UUIDs.
#
# Per #393 plan: catalog_control_parts is read-only (display only); SSP
# and CDEF statements are editable on `implementation_prose`,
# `responsible_roles_data`, `set_parameters_data` only -- statement_id
# and label are immutable references to the catalog.
class CreateStatementAndPartTables < ActiveRecord::Migration[8.1]
  def up
    create_table :ssp_control_statements, if_not_exists: true do |t|
      t.references :ssp_control, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string   :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string   :statement_id, null: false
      t.string   :label
      t.string   :parent_statement_id
      t.text     :implementation_prose
      t.text     :remarks
      t.jsonb    :responsible_roles_data, default: []
      t.jsonb    :set_parameters_data, default: []
      t.integer  :row_order, default: 0, null: false
      t.timestamps
    end
    add_idx(:ssp_control_statements, [ :ssp_control_id, :statement_id ],
            name: "idx_ssp_stmt_on_ctrl_sid", unique: true)
    add_idx(:ssp_control_statements, :uuid, name: "idx_ssp_stmt_on_uuid", unique: true)

    create_table :cdef_control_statements, if_not_exists: true do |t|
      t.references :cdef_control, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string   :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string   :statement_id, null: false
      t.string   :label
      t.string   :parent_statement_id
      t.text     :implementation_prose
      t.text     :remarks
      t.jsonb    :set_parameters_data, default: []
      t.integer  :row_order, default: 0, null: false
      t.timestamps
    end
    add_idx(:cdef_control_statements, [ :cdef_control_id, :statement_id ],
            name: "idx_cdef_stmt_on_ctrl_sid", unique: true)
    add_idx(:cdef_control_statements, :uuid, name: "idx_cdef_stmt_on_uuid", unique: true)

    create_table :catalog_control_parts, if_not_exists: true do |t|
      t.references :catalog_control, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string   :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string   :part_id, null: false
      t.string   :part_name, null: false
      t.string   :label
      t.string   :parent_part_id
      t.text     :prose
      t.jsonb    :props_data, default: []
      t.integer  :row_order, default: 0, null: false
      t.timestamps
    end
    add_idx(:catalog_control_parts, [ :catalog_control_id, :part_id ],
            name: "idx_cat_parts_on_ctrl_pid", unique: true)
    add_idx(:catalog_control_parts, [ :catalog_control_id, :part_name ],
            name: "idx_cat_parts_on_ctrl_name")

    unless column_exists?(:sar_findings, :ssp_control_statement_id)
      add_reference :sar_findings, :ssp_control_statement,
                    null: true, foreign_key: { on_delete: :nullify }, index: true
    end
    unless column_exists?(:poam_items, :ssp_control_statement_id)
      add_reference :poam_items, :ssp_control_statement,
                    null: true, foreign_key: { on_delete: :nullify }, index: true
    end

    say_with_time "Backfilling SSP/CDEF statements + Catalog parts" do
      backfill_for(SspDocument)  { |doc| CatalogPartExtractorService.new(doc).backfill_ssp_statements! }
      backfill_for(CdefDocument) { |doc| CatalogPartExtractorService.new(doc).backfill_cdef_statements! }
      ControlCatalog.find_each do |cat|
        ApplicationRecord.transaction(requires_new: true) do
          CatalogPartExtractorService.backfill_catalog_parts!(cat)
        end
      rescue StandardError => e
        Rails.logger.warn("[#{self.class.name}] catalog parts backfill failed for ##{cat.id}: #{e.message}")
      end
    end
  end

  def down
    if column_exists?(:poam_items, :ssp_control_statement_id)
      remove_reference :poam_items, :ssp_control_statement, foreign_key: true
    end
    if column_exists?(:sar_findings, :ssp_control_statement_id)
      remove_reference :sar_findings, :ssp_control_statement, foreign_key: true
    end
    drop_table :catalog_control_parts,    if_exists: true
    drop_table :cdef_control_statements,  if_exists: true
    drop_table :ssp_control_statements,   if_exists: true
  end

  private

  def add_idx(table, cols, name:, unique: false)
    return if index_exists?(table, cols, name: name)
    add_index table, cols, name: name, unique: unique
  end

  def backfill_for(document_class)
    document_class.find_each(batch_size: 50) do |doc|
      ApplicationRecord.transaction(requires_new: true) { yield doc }
    rescue StandardError => e
      Rails.logger.warn("[#{self.class.name}] backfill failed for #{document_class.name} ##{doc.id}: #{e.message}")
    end
  end
end
