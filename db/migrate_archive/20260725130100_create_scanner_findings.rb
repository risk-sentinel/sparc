# frozen_string_literal: true

# #447 — one control result from an ingested scan (translation state mirroring
# the uploaded HDF `controls[]`). Idempotent re-ingest: the same control within
# the same boundary UPDATES the current finding and repoints it to the latest
# scan_run (unique index on [authorization_boundary_id, control_id]) rather than
# duplicating. Dispositions attach to (boundary, control_id), not to a scan_run,
# so they survive re-scans and naturally drop from export when the control_id
# stops appearing in fresh scanner output.
#
# NIST 800-53: CA-7 (continuous monitoring), RA-5 (vulnerability scanning),
# SI-2 (flaw remediation tracking).
class CreateScannerFindings < ActiveRecord::Migration[8.1]
  def change
    create_table :scanner_findings do |t|
      t.references :scan_run, null: false, foreign_key: true
      # Denormalized boundary FK so scoping/idempotency queries don't join scan_runs.
      t.references :authorization_boundary, null: false, foreign_key: true
      t.string :control_id, null: false                 # HDF control id (CVE / rule id)
      t.string :status, null: false                     # passed|failed|skipped|error|notApplicable
      t.string :severity                                # CRITICAL|HIGH|MEDIUM|LOW|INFORMATIONAL
      t.text   :title
      t.text   :description
      t.string :scanner
      t.jsonb  :raw_hdf, null: false, default: {}        # the control's HDF slice (translation cache)
      t.string :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.timestamps
    end

    # Idempotent upsert key: one current finding per control per boundary.
    add_index :scanner_findings, [ :authorization_boundary_id, :control_id ], unique: true,
              name: "index_scanner_findings_on_boundary_and_control"
    add_index :scanner_findings, [ :authorization_boundary_id, :status ]
    add_index :scanner_findings, :uuid, unique: true
  end
end
