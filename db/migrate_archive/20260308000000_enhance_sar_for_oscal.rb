class EnhanceSarForOscal < ActiveRecord::Migration[8.1]
  def change
    # ── A. Expand sar_documents with OSCAL assessment-results fields ──
    change_table :sar_documents, bulk: true do |t|
      t.string   :creation_method, default: "excel"
      t.string   :oscal_version
      t.text     :description
      t.string   :import_ap_href
      t.datetime :assessment_start
      t.datetime :assessment_end
      t.jsonb    :metadata_extra, default: {}
      t.jsonb    :import_metadata, default: {}
      t.jsonb    :reviewed_controls_data, default: {}
      t.jsonb    :assessment_log_data, default: []
      t.jsonb    :local_definitions_extra, default: {}
    end

    add_reference :sar_documents, :sap_document,
                  foreign_key: { on_delete: :nullify }, null: true

    # ── B. sar_results (container for observations/findings/risks) ──
    create_table :sar_results do |t|
      t.references :sar_document, null: false, foreign_key: { on_delete: :cascade }
      t.string   :uuid, null: false
      t.string   :title
      t.text     :description
      t.datetime :start_time, null: false
      t.datetime :end_time
      t.jsonb    :reviewed_controls_data, default: {}
      t.jsonb    :assessment_log_data, default: []
      t.jsonb    :attestations_data, default: []
      t.jsonb    :props_data, default: []
      t.jsonb    :links_data, default: []
      t.text     :remarks
      t.integer  :position, default: 0
      t.timestamps
    end
    add_index :sar_results, [ :sar_document_id, :uuid ],
              unique: true, name: "idx_sar_results_doc_uuid"

    # ── C. sar_observations ──
    create_table :sar_observations do |t|
      t.references :sar_result, null: false, foreign_key: { on_delete: :cascade }
      t.string   :uuid, null: false
      t.string   :title
      t.text     :description
      t.datetime :collected
      t.datetime :expires
      t.jsonb    :methods_data, default: []
      t.jsonb    :types_data, default: []
      t.jsonb    :origins_data, default: []
      t.jsonb    :subjects_data, default: []
      t.jsonb    :relevant_evidence_data, default: []
      t.jsonb    :props_data, default: []
      t.jsonb    :links_data, default: []
      t.text     :remarks
      t.timestamps
    end
    add_index :sar_observations, [ :sar_result_id, :uuid ],
              unique: true, name: "idx_sar_obs_result_uuid"

    # ── D. sar_findings ──
    create_table :sar_findings do |t|
      t.references :sar_result, null: false, foreign_key: { on_delete: :cascade }
      t.string   :uuid, null: false
      t.string   :title
      t.text     :description
      t.jsonb    :target_data, default: {}
      t.string   :implementation_statement_uuid
      t.jsonb    :origins_data, default: []
      t.jsonb    :props_data, default: []
      t.jsonb    :links_data, default: []
      t.text     :remarks
      t.timestamps
    end
    add_index :sar_findings, [ :sar_result_id, :uuid ],
              unique: true, name: "idx_sar_findings_result_uuid"

    # ── E. sar_risks ──
    create_table :sar_risks do |t|
      t.references :sar_result, null: false, foreign_key: { on_delete: :cascade }
      t.string   :uuid, null: false
      t.string   :title
      t.text     :description
      t.text     :statement
      t.string   :status
      t.string   :likelihood
      t.string   :impact
      t.datetime :deadline
      t.jsonb    :origins_data, default: []
      t.jsonb    :threat_ids_data, default: []
      t.jsonb    :characterizations_data, default: []
      t.jsonb    :mitigating_factors_data, default: []
      t.jsonb    :risk_log_data, default: {}
      t.jsonb    :remediations_data, default: []
      t.jsonb    :props_data, default: []
      t.jsonb    :links_data, default: []
      t.text     :remarks
      t.timestamps
    end
    add_index :sar_risks, [ :sar_result_id, :uuid ],
              unique: true, name: "idx_sar_risks_result_uuid"
    add_index :sar_risks, [ :sar_result_id, :status ],
              name: "idx_sar_risks_result_status"

    # ── F. sar_local_components ──
    create_table :sar_local_components do |t|
      t.references :sar_document, null: false, foreign_key: { on_delete: :cascade }
      t.string   :uuid, null: false
      t.string   :component_type
      t.string   :title
      t.text     :description
      t.string   :purpose
      t.string   :status_state
      t.text     :status_remarks
      t.jsonb    :responsible_roles_data, default: []
      t.jsonb    :protocols_data, default: []
      t.jsonb    :props_data, default: []
      t.jsonb    :links_data, default: []
      t.text     :remarks
      t.timestamps
    end
    add_index :sar_local_components, [ :sar_document_id, :uuid ],
              unique: true, name: "idx_sar_local_comp_doc_uuid"

    # ── G. Join tables ──
    create_table :sar_finding_observations do |t|
      t.references :sar_finding, null: false, foreign_key: { on_delete: :cascade }
      t.references :sar_observation, null: false, foreign_key: { on_delete: :cascade }
    end
    add_index :sar_finding_observations, [ :sar_finding_id, :sar_observation_id ],
              unique: true, name: "idx_sar_finding_obs_unique"

    create_table :sar_finding_risks do |t|
      t.references :sar_finding, null: false, foreign_key: { on_delete: :cascade }
      t.references :sar_risk, null: false, foreign_key: { on_delete: :cascade }
    end
    add_index :sar_finding_risks, [ :sar_finding_id, :sar_risk_id ],
              unique: true, name: "idx_sar_finding_risk_unique"

    create_table :sar_risk_observations do |t|
      t.references :sar_risk, null: false, foreign_key: { on_delete: :cascade }
      t.references :sar_observation, null: false, foreign_key: { on_delete: :cascade }
    end
    add_index :sar_risk_observations, [ :sar_risk_id, :sar_observation_id ],
              unique: true, name: "idx_sar_risk_obs_unique"
  end
end
