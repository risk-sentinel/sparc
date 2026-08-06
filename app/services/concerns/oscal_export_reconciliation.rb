# frozen_string_literal: true

# Refuse to publish OSCAL naming controls that exist in no loaded catalog
# (#911, layer 2 of 3).
#
# ── Why the schema cannot do this for us ────────────────────────────────────
#
# `control-id` is **TokenDatatype** — it constrains the CHARACTER SET, not
# existence. Measured on real spreadsheet input:
#
#     "See note"       -> "see-note"        OSCAL token? true
#     "TBD"            -> "tbd"             OSCAL token? true
#     "Not applicable" -> "not-applicable"  OSCAL token? true
#
# `OscalSchemaValidationService` passes all three, so without this check SPARC
# publishes an SSP asserting an implemented requirement against a control named
# `tbd`, and every downstream consumer accepts it. Schema-validity is not OSCAL
# compliance.
#
# ── Refuse, do not omit ─────────────────────────────────────────────────────
#
# A row with an unrecognised identifier is a control its author INTENDED to
# claim. Silently dropping it produces a document that looks complete and is
# not, which is worse than one that refuses — an incomplete SSP presented as
# whole is a false assurance.
#
# This differs from an unmapped STIG rule, which carries no control identifier
# at all and was never a claim of implementing anything; those are omitted.
#
# NIST 800-53: CA-2, CA-5, PM-6 — an assessment artifact must reference controls
# that actually exist in the baseline it claims to implement.
module OscalExportReconciliation
  private

  # @param label [String] document type, for the message
  # @param name [String] document name
  # @param control_ids [Enumerable<String>] every identifier the export will emit
  def refuse_unresolvable_controls!(label:, name:, control_ids:)
    unresolvable = unresolvable_control_ids(control_ids)
    return if unresolvable.empty?

    shown = unresolvable.first(10)
    suffix = unresolvable.size > shown.size ? " (and #{unresolvable.size - shown.size} more)" : ""

    raise OscalValidationError,
          "#{label} \"#{name}\" references #{unresolvable.size} " \
          "#{'control'.pluralize(unresolvable.size)} that exist in no loaded catalog: " \
          "#{shown.join(', ')}#{suffix}. OSCAL export would name controls nothing can " \
          "resolve, so it is refused. Load the catalog or profile these controls come " \
          "from, or correct the identifiers, then export again."
  end

  # One query for the whole document rather than one per control: a large SSP
  # has hundreds of rows, and `CatalogControl.resolvable?` per row would turn an
  # export into hundreds of round trips.
  def unresolvable_control_ids(control_ids)
    candidates = Array(control_ids).reject(&:blank?)
                                   .map { |id| ControlId.canonical(id) }
                                   .reject { |id| id == "unknown" }
                                   .uniq
    return [] if candidates.empty?

    known = CatalogControl.unscoped
                          .where(control_id: candidates)
                          .or(CatalogControl.unscoped.where(canonical_id: candidates))
                          .pluck(:control_id, :canonical_id)
                          .flatten.compact.to_set

    candidates.reject { |id| known.include?(id) }
  end
end
