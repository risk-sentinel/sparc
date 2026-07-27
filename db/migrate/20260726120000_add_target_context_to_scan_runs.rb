# frozen_string_literal: true

# #811 Part 1 — bind a scan to the target/CDEF it ran against, and record whether
# the scanner is target-specific (trivy/secrets) or boundary-wide (AWS Config).
# The original scan file is persisted via ActiveStorage (has_one_attached :file),
# so no column is needed for it.
class AddTargetContextToScanRuns < ActiveRecord::Migration[8.1]
  def change
    add_reference :scan_runs, :cdef_document, null: true, index: true,
                  foreign_key: { on_delete: :nullify }
    add_column :scan_runs, :scanner_scope, :string, default: "target", null: false
  end
end
