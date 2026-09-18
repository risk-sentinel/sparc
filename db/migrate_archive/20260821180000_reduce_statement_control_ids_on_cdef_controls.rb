# #1030 — `control_id` on a CDEF control is a catalog join key, and for
# STIG-derived rows it held a statement-level reference that joined to nothing.
#
# The CCI mapping data is statement-level (`cm-6-b`, `ac-7-a`, `pm-14-a-1`).
# NIST catalogs hold controls and enhancements and never statement parts, so
# every such row matched no `CatalogControl` at all. Measured across
# `lib/data_mappings/cci_to_nist.json`: only 42.9% of its 4,569 mappings named
# an id present in the catalog; 95.2% do once reduced to the control.
#
# Nothing errored. Coverage and gap analysis simply reported no match for these
# rows, which reads as "not implemented" rather than as a broken reference.
#
# The parsers now reduce at the resolution boundary via `ControlId.control_key`,
# so new ingests are correct. This handles the rows already stored.
#
# ── Why the scope is what it is ──────────────────────────────────────────────
#
# Only rows carrying a `nist_controls` field are touched. That field is written
# exactly when `control_id` came from NIST resolution, so it is the marker
# separating "this id is a NIST reference" from "this id is whatever the source
# profile called its control". A plain InSpec CDEF keeps its own control name in
# `control_id`, and a name like `abc-123-def` would otherwise be truncated to
# `abc-123` by a blanket reduction. The parsers apply the same distinction: they
# reduce `nist_id` and never `fallback_id`.
#
# The statement detail is not lost — it is already in `nist_controls`, which is
# where the reduced part continues to live.
#
# Idempotent: `control_key` is idempotent, so a second run finds every row
# already reduced and updates nothing.
class ReduceStatementControlIdsOnCdefControls < ActiveRecord::Migration[8.1]
  def up
    scope = CdefControl
              .where.not(control_id: nil)
              .where(id: CdefControlField.where(field_name: "nist_controls").select(:cdef_control_id))

    reduced = 0
    scope.find_each do |control|
      key = ControlId.control_key(control.control_id)
      next if key == control.control_id

      # update_columns: this is a value correction, not an edit. Callbacks would
      # re-run `canonicalises_control_id` (a no-op on an already-canonical id)
      # and bump `updated_at` on 51,690-row instances for no reason.
      control.update_columns(control_id: key)
      reduced += 1
    end

    if reduced.zero?
      say "No statement-level control ids to reduce"
    else
      say "Reduced #{reduced} statement-level control id(s) to the control they belong to"
    end
  end

  # Not reversible: the pre-reduction value is a statement reference that
  # `nist_controls` still holds, so nothing is lost, but which rows previously
  # carried which spelling is not recoverable from the reduced form.
  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
