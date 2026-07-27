# frozen_string_literal: true

# #811 Part 1+2 — component/target association + re-occurrence lifecycle history.
#
# Findings become per-scan_run rows (history), each flagged `current`. Exactly one
# CURRENT finding per (boundary, control_id) — a partial unique index replaces the
# old plain unique index — while prior scans are retained for N-vs-N-1 diffing
# (carry-forward / re_failed / expired / drift). Existing rows default to current.
class AddLifecycleToScannerFindings < ActiveRecord::Migration[8.1]
  def change
    add_column :scanner_findings, :component_ref, :string    # purl / image digest / hostname
    add_column :scanner_findings, :source_location, :string  # source file / location the finding points at
    add_reference :scanner_findings, :cdef_document, null: true, index: true,
                  foreign_key: { on_delete: :nullify }
    add_column :scanner_findings, :lifecycle_status, :string, default: "new", null: false
    add_column :scanner_findings, :current, :boolean, default: true, null: false

    remove_index :scanner_findings, name: "index_scanner_findings_on_boundary_and_control"
    add_index :scanner_findings, [ :authorization_boundary_id, :control_id ],
              unique: true, where: "current",
              name: "index_scanner_findings_current_boundary_control"
    add_index :scanner_findings, [ :authorization_boundary_id, :current ]
  end
end
