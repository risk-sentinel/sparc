class CreateSapAndSarControlObjectives < ActiveRecord::Migration[8.1]
  def up
    create_table :sap_control_objectives, if_not_exists: true do |t|
      t.references :sap_control, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string   :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string   :objective_id, null: false
      t.string   :label
      t.string   :parent_objective_id
      t.text     :prose
      t.string   :status, null: false, default: "pending"
      t.string   :assessor_name
      t.text     :assessor_notes
      t.datetime :assessed_at
      t.integer  :row_order, default: 0, null: false
      t.timestamps
    end

    unless index_exists?(:sap_control_objectives, [ :sap_control_id, :objective_id ], name: "idx_sap_obj_on_ctrl_oid")
      add_index :sap_control_objectives, [ :sap_control_id, :objective_id ],
                unique: true, name: "idx_sap_obj_on_ctrl_oid"
    end
    unless index_exists?(:sap_control_objectives, [ :sap_control_id, :status ], name: "idx_sap_obj_on_ctrl_status")
      add_index :sap_control_objectives, [ :sap_control_id, :status ],
                name: "idx_sap_obj_on_ctrl_status"
    end
    add_index :sap_control_objectives, :uuid, unique: true unless index_exists?(:sap_control_objectives, :uuid)

    create_table :sar_control_objectives, if_not_exists: true do |t|
      t.references :sar_control, null: false, foreign_key: { on_delete: :cascade }, index: true
      t.string   :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string   :objective_id, null: false
      t.string   :label
      t.string   :parent_objective_id
      t.text     :prose
      t.string   :status, null: false, default: "pending"
      t.string   :assessor_name
      t.text     :assessor_notes
      t.datetime :assessed_at
      t.integer  :row_order, default: 0, null: false
      t.timestamps
    end

    unless index_exists?(:sar_control_objectives, [ :sar_control_id, :objective_id ], name: "idx_sar_obj_on_ctrl_oid")
      add_index :sar_control_objectives, [ :sar_control_id, :objective_id ],
                unique: true, name: "idx_sar_obj_on_ctrl_oid"
    end
    unless index_exists?(:sar_control_objectives, [ :sar_control_id, :status ], name: "idx_sar_obj_on_ctrl_status")
      add_index :sar_control_objectives, [ :sar_control_id, :status ],
                name: "idx_sar_obj_on_ctrl_status"
    end
    add_index :sar_control_objectives, :uuid, unique: true unless index_exists?(:sar_control_objectives, :uuid)

    # Nullable FK -- existing sar_findings predate per-objective tracking and
    # may legitimately reference a control without a specific objective.
    unless column_exists?(:sar_findings, :sar_control_objective_id)
      add_reference :sar_findings, :sar_control_objective,
                    null: true, foreign_key: { on_delete: :nullify }, index: true
    end

    # Backfill is best-effort. The extractor reads from the linked profile's
    # resolved_catalog_json. Documents without a profile get flagged for
    # later re-association via the existing "Associate Source" UI rather
    # than failing the migration.
    say_with_time "Backfilling SAP/SAR control objectives from linked profiles" do
      backfill_objectives_for(SapDocument)
      backfill_objectives_for(SarDocument)
    end
  end

  def down
    if column_exists?(:sar_findings, :sar_control_objective_id)
      remove_reference :sar_findings, :sar_control_objective, foreign_key: true
    end
    drop_table :sar_control_objectives, if_exists: true
    drop_table :sap_control_objectives, if_exists: true
  end

  private

  def backfill_objectives_for(document_class)
    document_class.find_each(batch_size: 50) do |doc|
      ApplicationRecord.transaction(requires_new: true) do
        ControlObjectiveExtractorService.new(doc).backfill!
      end
    rescue StandardError => e
      Rails.logger.warn(
        "[#{self.class.name}] backfill failed for #{document_class.name} ##{doc.id}: #{e.message}"
      )
    end
  end
end
