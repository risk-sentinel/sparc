# frozen_string_literal: true

# #447 — the human triage decision SPARC translates to an HDF Amendment override.
# Bound to a finding by (authorization_boundary_id, control_id) rather than a
# scan_run FK, so a disposition survives re-ingest of a fresh scan and only drops
# from export when the control_id stops appearing. `linked_subject` is polymorphic
# to the justifying artefact (Evidence / PoamFinding / AuthorizationBoundary /
# RiskAssessment) depending on `kind`. `signature_hash` binds tenant-supplied
# inputs for provenance — SPARC binds, it does not author.
#
# NIST 800-53: SI-2 (flaw remediation), CA-7 (continuous monitoring),
# AU-10 (non-repudiation via signature_hash), AU-12 (audit).
class CreateFindingDispositions < ActiveRecord::Migration[8.1]
  def change
    create_table :finding_dispositions do |t|
      t.references :authorization_boundary, null: false, foreign_key: true
      t.string   :control_id, null: false
      t.string   :kind, null: false                      # falsePositive|waiver|poam|vendorDependency|inherited|riskAdjustment|operationalRequirement
      t.text     :reason, null: false
      t.datetime :expiration                             # required for waiver / operationalRequirement
      t.string   :linked_subject_type                    # polymorphic justifying artefact
      t.bigint   :linked_subject_id
      t.string   :signature_hash                         # provenance over tenant-supplied inputs
      t.string   :decided_by, null: false
      t.datetime :decided_at, null: false
      t.string   :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.timestamps
    end

    # One active disposition per finding (boundary + control).
    add_index :finding_dispositions, [ :authorization_boundary_id, :control_id ], unique: true,
              name: "index_finding_dispositions_on_boundary_and_control"
    add_index :finding_dispositions, [ :linked_subject_type, :linked_subject_id ]
    add_index :finding_dispositions, :uuid, unique: true
  end
end
