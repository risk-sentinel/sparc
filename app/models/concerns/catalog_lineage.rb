# frozen_string_literal: true

# Catalog lineage (#911, layer 2 of 3).
#
# OSCAL makes the import MANDATORY at every hop — profile -> catalog,
# ssp -> profile, sap -> ssp, sar -> ap, cdef -> @source. SPARC models the same
# chain but makes each hop `optional: true`, so a document authored in SPARC can
# end up unable to name the catalog it descends from. The columns already exist
# and the OSCAL parsers already read the hrefs; they are simply unpopulated for
# documents SPARC authored rather than imported. Both seeded SSPs came from
# `demo_acme_*.xlsx`, which carries no OSCAL lineage at all.
#
# That chain is what makes a control identifier mean anything. Layer 1 made
# identifiers comparable; without lineage they are still only comparable to
# "some control in some loaded catalog", which is not a baseline.
#
# ── What this concern does, and does not do ─────────────────────────────────
#
# It reports. It does not block, rewrite, or infer. Whether an unresolved
# document may still be updated is the caller's decision (the gate), and
# membership — is this control in THIS document's baseline — is layer 3.
#
# **SPARC never synthesises a profile from a document's own control set.** That
# would manufacture a baseline out of the very thing being validated, which is
# an unverifiable source. Where no suitable profile is loaded, the remedy is to
# load one, and SPARC says so plainly.
#
# ── Declaring lineage ───────────────────────────────────────────────────────
#
#   class SspDocument < ApplicationRecord
#     include CatalogLineage
#     lineage_via :profile_document,
#                 href:    :import_profile_href,
#                 label:   "profile",
#                 remedy:  "PATCH /api/v1/ssp_documents/:id { profile_document_id }",
#                 options: "/api/v1/profile_documents"
#   end
#
# `mode: :any` declares an either/or hop, which OSCAL permits for POA&M
# (import-ssp OR a system identifier).
#
# NIST 800-53: CA-2, CA-5, CM-3, PM-6 — a control reference is only meaningful
# against the baseline it was assessed under.
module CatalogLineage
  extend ActiveSupport::Concern

  # Advisory: worth reporting, never refuses a write.
  ADVISORY = [].freeze
  # Refuses an update until reconciled. Setting the baseline is itself allowed.
  BLOCKS_UPDATE = %w[update].freeze

  included do
    class_attribute :lineage_defs, instance_writer: false, default: [].freeze
    # The association holding this document's control references. Reconciliation
    # is meaningless before there are any, so this is what decides whether the
    # question even applies yet.
    class_attribute :lineage_control_association, instance_writer: false, default: nil
  end

  class_methods do
    # Declare one hop of the OSCAL import chain.
    #
    # @param associations [Array<Symbol>] the association(s) that satisfy it
    # @param key     [Symbol] stable slug for the issue code. Kept separate from
    #   `label` because the label is prose ("assessment plan", "SSP") and would
    #   otherwise produce codes like `missing_assessment plan_source` — a code
    #   with a space in it, which no integrator can match on.
    # @param href    [Symbol, nil] column holding the raw OSCAL href, when the
    #   document type carries one. A populated href with no resolved
    #   association is a DIFFERENT failure from no href at all — the import
    #   named something SPARC could not find, and reporting the two the same
    #   way hides a broken reference behind "not set yet".
    # @param traceable_via [Array<Symbol>] associations that do NOT satisfy the
    #   hop but, when present, mean controls still reach a catalog by another
    #   route. A SAR linked to its SSP is traceable (SSP -> profile -> catalog)
    #   yet still invalid OSCAL, because `import-ap` is required. That is a
    #   different problem from a SAR with no lineage at all, and an operator
    #   sizing the work needs to see which one they have. Still blocks.
    # @param mode    [:all, :any] `:any` for OSCAL's either/or hops
    # @param controls [Symbol] the association holding this document's control
    #   references. Until it has some, there is nothing to reconcile.
    # @param message [Hash] what a human and an integrator are told:
    #   `label:` the prose name of the baseline ("assessment plan"),
    #   `remedy:` the action that fixes it, `options:` where to find candidates.
    #   Grouped because the three are one concern — the reported wording — and
    #   splitting them pushed this signature past a readable arity.
    def lineage_via(*associations, key:, message:, controls: nil,
                    href: nil, traceable_via: [], mode: :all)
      self.lineage_control_association = controls if controls
      self.lineage_defs = lineage_defs + [ {
        associations: associations.flatten.map(&:to_sym),
        key: key.to_sym, href: href, mode: mode,
        label: message.fetch(:label),
        remedy: message.fetch(:remedy),
        options: message[:options],
        traceable_via: Array(traceable_via).map(&:to_sym)
      }.freeze ]
    end

    # The attributes that, when supplied, declare this document's baseline.
    #
    # The gate lets a write through when it carries one of these. Without that
    # exemption the gate would have no exit: an unresolved document could never
    # be updated, and setting the baseline IS an update. Declaring the baseline
    # is the one write that must always be permitted.
    def lineage_attribute_names
      lineage_defs.flat_map { |definition|
        definition[:associations].map { |name| :"#{name}_id" }
      }.uniq
    end
  end

  # What a human can choose from to declare this document's baseline, derived
  # from the association rather than a hand-kept list so it cannot drift from
  # the lineage declaration.
  #
  # **These are the things already LOADED.** SPARC never offers to synthesise a
  # profile from the document's own control set — that would manufacture a
  # baseline out of the very thing being validated. When a collection comes back
  # empty the honest answer is that the operator must load the right profile or
  # catalog first, and the banner says exactly that rather than offering a
  # plausible-looking substitute.
  def lineage_choices
    self.class.lineage_defs.flat_map do |definition|
      definition[:associations].map do |name|
        klass = self.class.reflect_on_association(name).klass
        # "Profile document" -> "Profile". The model name is an implementation
        # detail; the banner is prose a person reads.
        label = klass.model_name.human.sub(/\s+document\z/i, "")
        { attribute: :"#{name}_id", label: label, records: choosable(klass) }
      end
    end
  end

  # Does this set of attributes declare a baseline? Blank values do not count —
  # clearing the FK is not reconciling, and treating it as such would let a
  # caller slip any edit past the gate by sending `profile_document_id: ""`.
  def lineage_resolving_write?(attributes)
    return false if attributes.blank?

    normalised = attributes.to_h.transform_keys(&:to_sym)
    self.class.lineage_attribute_names.any? { |name| normalised[name].present? }
  end

  # #928 — does this set of attributes REPOINT a published document at a
  # different baseline?
  #
  # The inverse of `lineage_resolving_write?` and deliberately narrower than
  # "is it published". Setting a baseline that is MISSING must stay permitted
  # even on a published document: anything published before #911 shipped can be
  # both published and unreconciled, and refusing those wholesale would leave
  # them permanently unreconcilable — the exact trap the gate was built to
  # avoid. Swapping a baseline that is already set is the write to stop, because
  # lineage exists to give change control something approved to change against,
  # and silently repointing an approved document invalidates every assessment
  # made against it.
  #
  # Lives on the model rather than in a controller concern because both
  # surfaces need it: the web reaches it through `set_baseline`, the API through
  # `PATCH /api/v1/profile_documents/:id { control_catalog_id }`. A
  # controller-side check would have covered one of the two, which is the drift
  # #919 spent a whole PR closing.
  #
  # NIST 800-53: CM-3 (configuration change control), CA-5.
  def rebaselining_published?(attributes)
    return false unless respond_to?(:published_lifecycle?)
    return false unless published_lifecycle?
    return false if attributes.blank?

    normalised = attributes.to_h.transform_keys(&:to_sym)
    self.class.lineage_attribute_names.any? do |name|
      current = public_send(name)
      supplied = normalised[name]
      current.present? && supplied.present? && current.to_s != supplied.to_s
    end
  end

  # Every unresolved hop, as machine-readable issues.
  #
  # A document that references NO controls has nothing to trace, so it has
  # nothing to reconcile. Reporting one would be incoherent — the complaint is
  # that "controls cannot be traced to a catalog", and there are no controls —
  # and it had a concrete cost: `create` is not gated but `update` is, so the
  # API let an integrator create a document and then refused every edit to it.
  # POST-then-PATCH is the normal authoring flow, and it was broken for all six
  # types. The prompt now appears when it becomes meaningful: once the document
  # actually claims controls.
  def lineage_issues
    return [] unless references_controls?

    self.class.lineage_defs.filter_map { |definition| issue_for(definition) }
  end

  # Does this document claim any control at all?
  def references_controls?
    association = self.class.lineage_control_association
    return true if association.blank? # undeclared: assume it does, and report

    public_send(association).exists?
  end

  def lineage_resolved?
    lineage_issues.empty?
  end

  # Issues beyond the import chain. Override per type — CdefDocument reports
  # STIG rules that resolved to no NIST control this way (#911 commit 1).
  #
  # Layer 3's membership findings arrive here too, so lineage, unmapped rules and
  # out-of-baseline controls reach the reader as ONE account of their document
  # rather than three separately-worded warnings about the same thing.
  def additional_reconciliation_issues
    respond_to?(:membership_issues) ? membership_issues : []
  end

  # The whole picture, in ONE shape.
  #
  # The same object is returned whether it is advisory or the body of a 422
  # refusal, so an integrator writes one handler rather than discovering a
  # second shape the first time a write is refused. `blocking` is the field
  # that distinguishes them, not the response's structure.
  def reconciliation
    issues = lineage_issues + additional_reconciliation_issues
    return nil if issues.empty?

    {
      status: "unresolved",
      blocking: lineage_resolved? ? ADVISORY : BLOCKS_UPDATE,
      issues: issues
    }
  end

  # An update is refused while a mandatory OSCAL import is missing. Membership
  # findings never reach here — a system legitimately implements more than its
  # baseline, and refusing on that would make documents uneditable pending a
  # profile import their author may not control.
  def reconciliation_blocks_update?
    !lineage_resolved?
  end

  private

  # Soft-deleted documents must never be offered as a baseline: they are
  # invisible everywhere else, and relating live work to one would create a
  # reference the rest of the app cannot resolve. `default_scope` already
  # excludes them where the model is soft-deletable, so this only orders.
  def choosable(klass)
    scope = klass.all
    scope = scope.order(:name) if klass.column_names.include?("name")
    scope
  end

  def issue_for(definition)
    resolved = definition[:associations].map { |name| public_send(name).present? }
    satisfied = definition[:mode] == :any ? resolved.any? : resolved.all?
    return nil if satisfied

    href = definition[:href] && public_send(definition[:href]).presence
    traceable = definition[:traceable_via].any? { |name| public_send(name).present? }

    code, message =
      if href
        [ "unresolved_#{definition[:key]}_source", unresolved_href_message(definition, href) ]
      elsif traceable
        [ "incomplete_#{definition[:key]}_source", incomplete_source_message(definition) ]
      else
        [ "missing_#{definition[:key]}_source", missing_source_message(definition) ]
      end

    { code: code, message: message, remedy: definition[:remedy], options: definition[:options] }.compact
  end

  # The import named something SPARC cannot find. This is worse than an absent
  # baseline, not better: a reference that cannot be mapped back is broken at
  # the root, and everything downstream inherits it.
  def unresolved_href_message(definition, href)
    "This document imports #{definition[:label]} #{href.inspect}, which does not " \
    "resolve to anything loaded in SPARC. Controls cannot be traced to a catalog."
  end

  def missing_source_message(definition)
    "No imported #{definition[:label]}; controls cannot be traced to a catalog."
  end

  # Traceable by another route, but still not the import OSCAL requires. Saying
  # "cannot be traced to a catalog" here would be false, and an operator who
  # acted on it would go looking for the wrong problem.
  def incomplete_source_message(definition)
    "No imported #{definition[:label]}. Controls are traceable to a catalog " \
    "through this document's other links, but OSCAL requires the " \
    "#{definition[:label]} import, so export will not validate without it."
  end
end
