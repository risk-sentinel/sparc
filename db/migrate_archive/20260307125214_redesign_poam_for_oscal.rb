class RedesignPoamForOscal < ActiveRecord::Migration[8.1]
  def change
    # === A. Create 6 entity tables ===

    # 1. poam_risks — Top-level risk records
    create_table :poam_risks do |t|
      t.references :poam_document, null: false, foreign_key: { on_delete: :cascade }
      t.string  :uuid, null: false
      t.string  :title
      t.text    :description
      t.text    :statement
      t.string  :status
      t.string  :likelihood
      t.string  :impact
      t.datetime :deadline
      t.jsonb   :origins_data, default: []
      t.jsonb   :threat_ids_data, default: []
      t.jsonb   :characterizations_data, default: []
      t.jsonb   :mitigating_factors_data, default: []
      t.jsonb   :risk_log_data, default: {}
      t.jsonb   :props_data, default: []
      t.jsonb   :links_data, default: []
      t.text    :remarks
      t.timestamps
    end
    add_index :poam_risks, [ :poam_document_id, :uuid ], unique: true
    add_index :poam_risks, [ :poam_document_id, :status ]

    # 2. poam_observations — Top-level observation records
    create_table :poam_observations do |t|
      t.references :poam_document, null: false, foreign_key: { on_delete: :cascade }
      t.string  :uuid, null: false
      t.string  :title
      t.text    :description
      t.datetime :collected
      t.datetime :expires
      t.jsonb   :methods_data, default: []
      t.jsonb   :types_data, default: []
      t.jsonb   :origins_data, default: []
      t.jsonb   :subjects_data, default: []
      t.jsonb   :relevant_evidence_data, default: []
      t.jsonb   :props_data, default: []
      t.jsonb   :links_data, default: []
      t.text    :remarks
      t.timestamps
    end
    add_index :poam_observations, [ :poam_document_id, :uuid ], unique: true

    # 3. poam_findings — Top-level finding records
    create_table :poam_findings do |t|
      t.references :poam_document, null: false, foreign_key: { on_delete: :cascade }
      t.string  :uuid, null: false
      t.string  :title
      t.text    :description
      t.jsonb   :target_data, default: {}
      t.string  :implementation_statement_uuid
      t.jsonb   :origins_data, default: []
      t.jsonb   :props_data, default: []
      t.jsonb   :links_data, default: []
      t.text    :remarks
      t.timestamps
    end
    add_index :poam_findings, [ :poam_document_id, :uuid ], unique: true

    # 4. poam_remediations — Response objects within risks
    create_table :poam_remediations do |t|
      t.references :poam_risk, null: false, foreign_key: { on_delete: :cascade }
      t.string  :uuid, null: false
      t.string  :lifecycle
      t.string  :title
      t.text    :description
      t.jsonb   :origins_data, default: []
      t.jsonb   :required_assets_data, default: []
      t.jsonb   :props_data, default: []
      t.jsonb   :links_data, default: []
      t.text    :remarks
      t.integer :position, default: 0
      t.timestamps
    end
    add_index :poam_remediations, [ :poam_risk_id, :uuid ]

    # 5. poam_milestones — Task/milestone objects within remediations
    create_table :poam_milestones do |t|
      t.references :poam_remediation, null: false, foreign_key: { on_delete: :cascade }
      t.string  :uuid, null: false
      t.string  :milestone_type, default: "milestone"
      t.string  :title
      t.text    :description
      t.date    :due_date
      t.jsonb   :timing_data, default: {}
      t.jsonb   :dependencies_data, default: []
      t.jsonb   :responsible_roles_data, default: []
      t.jsonb   :subjects_data, default: []
      t.jsonb   :props_data, default: []
      t.jsonb   :links_data, default: []
      t.text    :remarks
      t.integer :position, default: 0
      t.timestamps
    end
    add_index :poam_milestones, [ :poam_remediation_id, :uuid ]

    # 6. poam_local_components — Components from local-definitions
    create_table :poam_local_components do |t|
      t.references :poam_document, null: false, foreign_key: { on_delete: :cascade }
      t.string  :uuid, null: false
      t.string  :component_type
      t.string  :title
      t.text    :description
      t.string  :purpose
      t.string  :status_state
      t.text    :status_remarks
      t.jsonb   :responsible_roles_data, default: []
      t.jsonb   :protocols_data, default: []
      t.jsonb   :props_data, default: []
      t.jsonb   :links_data, default: []
      t.text    :remarks
      t.timestamps
    end
    add_index :poam_local_components, [ :poam_document_id, :uuid ], unique: true

    # === B. Create 6 join tables ===

    create_table :poam_item_risks do |t|
      t.references :poam_item, null: false, foreign_key: { on_delete: :cascade }
      t.references :poam_risk, null: false, foreign_key: { on_delete: :cascade }
    end
    add_index :poam_item_risks, [ :poam_item_id, :poam_risk_id ], unique: true

    create_table :poam_item_observations do |t|
      t.references :poam_item, null: false, foreign_key: { on_delete: :cascade }
      t.references :poam_observation, null: false, foreign_key: { on_delete: :cascade }
    end
    add_index :poam_item_observations, [ :poam_item_id, :poam_observation_id ], unique: true, name: "idx_poam_item_obs_unique"

    create_table :poam_item_findings do |t|
      t.references :poam_item, null: false, foreign_key: { on_delete: :cascade }
      t.references :poam_finding, null: false, foreign_key: { on_delete: :cascade }
    end
    add_index :poam_item_findings, [ :poam_item_id, :poam_finding_id ], unique: true

    create_table :poam_risk_observations do |t|
      t.references :poam_risk, null: false, foreign_key: { on_delete: :cascade }
      t.references :poam_observation, null: false, foreign_key: { on_delete: :cascade }
    end
    add_index :poam_risk_observations, [ :poam_risk_id, :poam_observation_id ], unique: true, name: "idx_poam_risk_obs_unique"

    create_table :poam_finding_observations do |t|
      t.references :poam_finding, null: false, foreign_key: { on_delete: :cascade }
      t.references :poam_observation, null: false, foreign_key: { on_delete: :cascade }
    end
    add_index :poam_finding_observations, [ :poam_finding_id, :poam_observation_id ], unique: true, name: "idx_poam_finding_obs_unique"

    create_table :poam_finding_risks do |t|
      t.references :poam_finding, null: false, foreign_key: { on_delete: :cascade }
      t.references :poam_risk, null: false, foreign_key: { on_delete: :cascade }
    end
    add_index :poam_finding_risks, [ :poam_finding_id, :poam_risk_id ], unique: true

    # === C. Modify poam_documents ===
    remove_column :poam_documents, :observations_data, :jsonb
    remove_column :poam_documents, :risks_data, :jsonb
    add_column :poam_documents, :metadata_extra, :jsonb, default: {}
    add_column :poam_documents, :local_definitions_extra, :jsonb, default: {}

    # === D. Modify poam_items ===
    remove_column :poam_items, :related_risk_uuid, :string
    remove_column :poam_items, :related_observation_uuid, :string
    add_column :poam_items, :origins_data, :jsonb, default: []
    add_column :poam_items, :props_data, :jsonb, default: []
    add_column :poam_items, :links_data, :jsonb, default: []
    add_column :poam_items, :remarks, :text
    add_column :poam_items, :internal_notes, :text
    add_column :poam_items, :closure_evidence, :text

    # === E. Drop poam_item_fields ===
    drop_table :poam_item_fields
  end
end
