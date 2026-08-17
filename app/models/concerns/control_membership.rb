# frozen_string_literal: true

# Control membership (#911, layer 3 of 3).
#
# Layer 1 made identifiers comparable. Layer 2 made documents traceable to a
# catalog. This asks the question that only becomes answerable once both hold:
# is each control actually IN this document's baseline?
#
#     ProfileControl ⊆ its catalog       SspControl ⊆ its profile's selection
#     SapControl     ⊆ the SSP assessed  CdefControl ⊆ its @source
#
# That is a stronger claim than "this identifier exists somewhere". A control
# can be a real NIST control and still be out of scope for the system claiming
# it, and until now nothing could tell the difference.
#
# ── Reported, never blocking ────────────────────────────────────────────────
#
# A system legitimately implements more than its baseline — inherited controls,
# customer responsibilities, controls carried for a different framework. Blocking
# on this would make documents uneditable pending a profile import their author
# may not control.
#
# The measured case makes the point: relating the demo SSP to the only loaded
# profile flags **53 of its 55 controls**, because "Demo LOW Baseline" selects
# ten and is simply not that system's baseline. Refusing on that would be
# refusing on SPARC's own bad guess. It is a finding to act on, not an error.
#
# ── Degrading honestly ──────────────────────────────────────────────────────
#
# Where lineage is unresolved there is no baseline to compare against, so
# membership degrades to existence-in-any-catalog and SAYS SO. Reporting a
# weaker check as though it were authoritative is how a document comes to look
# verified when nothing verified it — the failure mode this whole issue exists
# to end.
#
# ── Two questions, both settled (#915) ──────────────────────────────────────
#
# **Cross-revision references do NOT count as in-baseline.** A baseline may
# contain additional controls, but it never mixes Rev 4 and Rev 5 standards — so
# a Rev 4 reference against a Rev 5 baseline is genuinely out of baseline, and
# the strict subset below is correct. Membership deliberately does NOT route
# through `ControlIdNormalizer.lookup_mapping`: translating across revisions here
# would assert an equivalence nobody verified, which is the class of false
# assurance this whole issue exists to remove.
#
# **Membership is judged at control id, not statement id.** Parts of a boundary
# can legitimately have partial coverage, and several parts may be required
# before a control is actually implemented — so a partially covered control is a
# normal intermediate state, not a membership failure. Catalogs do store
# statement sub-parts as rows (1936 of 4054 in the seeded Rev 5 catalog), and a
# CDEF can implement at statement level; that granularity belongs to coverage
# reporting, not to "is this control in scope".
#
# NIST 800-53: CA-2, CA-5, PM-6 — controls are assessed against the baseline the
# system was authorized under, not against the union of everything loaded.
module ControlMembership
  extend ActiveSupport::Concern

  # How much authority the answer carries.
  AUTHORITATIVE = :authoritative  # compared against this document's own baseline
  DEGRADED      = :degraded       # lineage unresolved — existence check only
  UNAVAILABLE   = :unavailable    # nothing loaded to compare against at all

  included do
    class_attribute :membership_def, instance_writer: false, default: nil
  end

  class_methods do
    # @param controls [Symbol] this document's own controls association
    # @param baseline [Symbol] the lineage association holding the baseline
    # @param baseline_controls [Symbol] the controls association ON that baseline
    # @param label [String] prose name of the baseline, for the message
    def membership_within(controls:, baseline:, baseline_controls:, label:)
      self.membership_def = {
        controls: controls, baseline: baseline,
        baseline_controls: baseline_controls, label: label
      }.freeze
    end
  end

  # Identifiers in this document that are not in its baseline.
  #
  # Compared canonically on both sides: a baseline storing `AC-02` and a document
  # storing `ac-2` name the same control, and a literal comparison here would
  # report every row as out-of-baseline — the exact false alarm layer 1 exists
  # to prevent, and a spectacular way to destroy trust in this check.
  def out_of_baseline_control_ids
    return [] if membership_def.blank?

    mine = own_control_ids
    return [] if mine.empty?

    permitted = baseline_control_id_set
    return [] if permitted.nil?

    mine.reject { |id| permitted.include?(id) }
  end

  def membership_authority
    return UNAVAILABLE if membership_def.blank?
    return AUTHORITATIVE if baseline_record.present?

    CatalogControl.exists? ? DEGRADED : UNAVAILABLE
  end

  # Advisory only — folded into the same reconciliation object as lineage so a
  # reader gets one account of their document.
  def membership_issues
    out = out_of_baseline_control_ids
    return [] if out.empty?

    authority = membership_authority
    shown = out.first(10)
    suffix = out.size > shown.size ? " (and #{out.size - shown.size} more)" : ""

    [ {
      code: authority == AUTHORITATIVE ? "controls_outside_baseline" : "controls_not_in_any_catalog",
      count: out.size,
      authority: authority.to_s,
      message: membership_message(authority, out.size, shown, suffix),
      remedy: membership_remedy(authority)
    } ]
  end

  private

  def own_control_ids
    public_send(membership_def[:controls])
      .pluck(:control_id).compact_blank
      .map { |id| ControlId.canonical(id) }.uniq
  end

  def baseline_record
    public_send(membership_def[:baseline])
  end

  # nil means "no comparison is possible", which is different from "everything
  # is out of baseline" — returning an empty set for a missing baseline would
  # flag every control in the document.
  def baseline_control_id_set
    if (record = baseline_record)
      record.public_send(membership_def[:baseline_controls])
            .pluck(:control_id).compact_blank
            .map { |id| ControlId.canonical(id) }.to_set
    elsif CatalogControl.exists?
      CatalogControl.unscoped.pluck(:control_id, :canonical_id)
                    .flatten.compact_blank.map { |id| ControlId.canonical(id) }.to_set
    end
  end

  def membership_message(authority, count, shown, suffix)
    controls = "control".pluralize(count)
    # The verb has to agree too. A well-scoped document reports ONE stray
    # control far more often than many, so "1 control are not in" was the
    # common case, not the edge one.
    is_are   = count == 1 ? "is" : "are"
    matches  = count == 1 ? "matches" : "match"

    if authority == AUTHORITATIVE
      "#{count} #{controls} #{is_are} not in this document's #{membership_def[:label]}: " \
      "#{shown.join(', ')}#{suffix}. A system may legitimately implement more than its " \
      "baseline, so this is reported rather than refused."
    else
      "#{count} #{controls} #{matches} no control in any loaded catalog: " \
      "#{shown.join(', ')}#{suffix}. This document has no #{membership_def[:label]}, so " \
      "SPARC can only check that the identifiers exist at all — not whether they are in scope."
    end
  end

  def membership_remedy(authority)
    if authority == AUTHORITATIVE
      "Confirm these are intended additions, or correct them against the #{membership_def[:label]}."
    else
      "Set this document's baseline to get an in-scope check instead of an existence check."
    end
  end
end
