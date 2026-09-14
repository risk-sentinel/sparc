# frozen_string_literal: true

# #447 — HDF Amendment triage layer. A ScanRun is one ingest event: a tenant
# uploads scanner output (HDF JSON, single scan or `saf convert` bundle) scoped
# to an AuthorizationBoundary. It is translation state, not the system of record —
# the tenant can re-upload a fresh scan at any time and SPARC reconciles.
#
# NIST 800-53: CA-7 (continuous monitoring), RA-5 (vulnerability scanning).
class CreateScanRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :scan_runs do |t|
      t.references :authorization_boundary, null: false, foreign_key: true
      t.string   :scanner, null: false                 # "trivy", "brakeman", "gitleaks", ...
      t.string   :scanner_version
      t.datetime :ingested_at, null: false
      t.integer  :finding_count, null: false, default: 0
      t.integer  :passed_count,  null: false, default: 0
      t.integer  :failed_count,  null: false, default: 0
      t.integer  :skipped_count, null: false, default: 0
      t.string   :source_filename
      t.string   :raw_hdf_digest                        # sha256 of the uploaded bundle (idempotency / audit)
      t.string   :created_by
      t.string   :uuid, null: false, default: -> { "gen_random_uuid()" }
      t.timestamps
    end

    add_index :scan_runs, :uuid, unique: true
    add_index :scan_runs, :raw_hdf_digest
  end
end
