# frozen_string_literal: true

# #1390 — a boundary's FedRAMP significant changes (SCN) and incidents (IEC).
#
#   fedramp_significant_changes  every change the provider evaluated: its type
#                                (Routine, Adaptive, Transformative; SCN-CSO-EVA),
#                                what a Significant Change Notification carries
#                                (SCN-CSO-INF), its start, finish and verification
#                                dates, and each notice sent, with the document
#                                sent (SCN-CSO-MAR, SCN-CSO-HIS)
#   fedramp_incidents            each incident evaluated (IEC-CSO-EFR): what an
#                                Incident Report carries, its N-rating history
#                                (IEC-CSO-EFI), lessons learned, and each report
#                                sent, with the document sent
#
# Neither is ever deleted: they are the provider's auditable records.
#
# Idempotent (docs/dev/issue_rules.md, migration rules 1–6).
class CreateFedrampChangesAndIncidents < ActiveRecord::Migration[8.1]
  def up
    create_table :fedramp_significant_changes, if_not_exists: true do |t|
      t.references :authorization_boundary, null: false, foreign_key: true, index: true
      t.string :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string :change_type, null: false
      t.text :description, null: false
      t.text :type_explanation
      t.text :reason
      t.text :customer_impact
      t.text :plan_summary
      t.date :planned_start
      t.date :planned_completion
      t.jsonb :milestones, null: false, default: []
      t.jsonb :impacted_controls, null: false, default: []
      t.text :impact_analysis
      t.string :assessor_name
      t.string :related_vulnerability
      t.string :approver_name
      t.string :approver_title
      t.text :new_risks
      t.boolean :emergency, null: false, default: false
      t.date :started_on
      t.date :finished_on
      t.date :verified_on
      t.jsonb :notices, null: false, default: []
      t.references :created_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }, index: true
      t.references :updated_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }, index: true
      t.timestamps
    end
    add_index :fedramp_significant_changes, :uuid, unique: true, if_not_exists: true

    create_table :fedramp_incidents, if_not_exists: true do |t|
      t.references :authorization_boundary, null: false, foreign_key: true, index: true
      t.string :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.string :tracking_id, null: false
      t.boolean :reportable, null: false, default: true
      t.string :coordinator
      t.text :description
      t.datetime :started_at
      t.datetime :detected_at
      t.string :detection_source
      t.datetime :evaluation_completed_at
      t.jsonb :milestones, null: false, default: []
      t.jsonb :ratings, null: false, default: []
      t.text :evaluation_notes
      t.text :functional_impact
      t.text :recovery_plan
      t.jsonb :affected_agencies, null: false, default: []
      t.text :observed_activity
      t.jsonb :indicators, null: false, default: []
      t.jsonb :related_cve_ids, null: false, default: []
      t.text :root_cause
      t.text :response_activities
      t.datetime :resolved_at
      t.jsonb :lessons_learned, null: false, default: []
      t.jsonb :reports, null: false, default: []
      t.references :created_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }, index: true
      t.references :updated_by, null: true, foreign_key: { to_table: :users, on_delete: :nullify }, index: true
      t.timestamps
    end
    add_index :fedramp_incidents, :uuid, unique: true, if_not_exists: true
    add_index :fedramp_incidents, %i[authorization_boundary_id tracking_id], unique: true, if_not_exists: true,
                                                                            name: "idx_fedramp_incidents_tracking"
  end

  def down
    drop_table :fedramp_incidents, if_exists: true
    drop_table :fedramp_significant_changes, if_exists: true
  end
end
