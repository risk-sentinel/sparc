# frozen_string_literal: true

# #940 — what does SPARC actually KNOW about this boundary?
#
# Read-only. Answers the question an onboarding team and their AO both have:
# how complete is this boundary's documentation, and what is still missing?
#
# WHAT THIS IS NOT
#
# The original spec described a scoring CLI with green/amber/red verdicts and a
# CI gate, organised into invented lifecycle phases. The owner redirected it
# (2026-09-12): what is wanted is a completeness report tied to the decisions a
# boundary actually makes when adopting OSCAL. So the sections here map 1:1 onto
# the wiki's "Adopting OSCAL" guide, not onto phases — a reader can move from a
# gap straight to the page that explains how to close it.
#
# FOUR STATES, AND THE FOURTH IS THE IMPORTANT ONE
#
#   :complete      SPARC holds what it needs
#   :partial       present but incomplete — the most actionable state
#   :absent        nothing recorded
#   :not_modelled  SPARC CANNOT ANSWER THIS. Not a failure of the boundary.
#
# `:not_modelled` exists because a completeness report that silently omits what
# it cannot see is worse than one that says so — it reads as "nothing to do"
# when the truth is "nobody can tell". Environments are the live example: the
# owner asked for "1 to n environments documented" and SPARC models environments
# nowhere, so the report says exactly that rather than scoring it.
#
# NIST 800-53: CA-2 (assessments), CA-5 (POA&M), PM-5 (system inventory).
class BoundaryReadinessService
  Section = Struct.new(:key, :title, :status, :count, :detail, :guide_anchor, keyword_init: true)

  STATES = %i[complete partial absent not_modelled].freeze

  def initialize(boundary)
    @boundary = boundary
    @ssp = boundary.ssp_document
  end

  def report
    {
      boundary: { id: @boundary.id, uuid: @boundary.uuid, name: @boundary.name, slug: @boundary.slug },
      sections: sections.map { |s| s.to_h },
      summary: summary
    }
  end

  def sections
    [
      personnel,
      classification,
      profile,
      ssp_section,
      components,
      back_matter,
      leveraged,
      cdefs,
      evidence,
      scans,
      environments
    ]
  end

  private

  attr_reader :boundary, :ssp

  def summary
    counts = sections.group_by(&:status).transform_values(&:size)
    STATES.index_with { |state| counts.fetch(state, 0) }
  end

  # ── The adoption decisions, in the order the guide asks them ─────────────

  # "A boundary with no Authorizing Official is not one anyone can act on."
  def personnel
    count = boundary.authorization_boundary_memberships.count
    roles = boundary.authorization_boundary_memberships.distinct.pluck(:role).compact

    Section.new(
      key: :personnel, title: "Personnel and roles", count: count,
      status: count.zero? ? :absent : (REQUIRED_ROLES.all? { |r| roles.include?(r) } ? :complete : :partial),
      detail: count.zero? ? "No one is on the roster" : "#{count} on the roster: #{roles.sort.join(', ')}",
      guide_anchor: "1-who-is-on-the-team-and-what-are-their-roles"
    )
  end

  # FIPS-199, read from the BOUNDARY (#940 S3) — the categorization is of the
  # system, derived as the high water mark across its information types. It
  # selects the baseline, so it is the one section that gates the usefulness of
  # several others.
  def classification
    level = boundary.security_categorization
    types = boundary.information_types.count
    conflict = boundary.categorization_conflicts_with_information_types?

    status = if level.blank? then :absent
    elsif conflict || types.zero? then :partial
    else :complete
    end

    Section.new(
      key: :classification, title: "Security categorization", count: types, status: status,
      detail: classification_detail(level, types, conflict),
      guide_anchor: "3-what-is-the-classification"
    )
  end

  def classification_detail(level, types, conflict)
    return "No FIPS-199 categorization, and no information types to derive one from" if level.blank?

    # The stored value is `fips-199-moderate`; a person reads "Moderate". This
    # string is rendered verbatim on the boundary screen, so it must not leak
    # the storage vocabulary.
    base = "#{SspInformationType.impact_label(level)} (FIPS-199 high water mark)"
    return "#{base}, but the recorded objectives CONTRADICT the information types" if conflict
    return "#{base}, recorded directly — no SP 800-60 information types justify it" if types.zero?

    "#{base} across #{types} information type(s)"
  end

  def profile
    doc = boundary.profile_document

    Section.new(
      key: :profile, title: "Profile / baseline", count: doc ? 1 : 0,
      status: doc ? :complete : :absent,
      detail: doc ? doc.name.to_s : "No baseline bound — controls are not yet determined",
      guide_anchor: "3-what-is-the-classification"
    )
  end

  def ssp_section
    Section.new(
      key: :ssp, title: "System Security Plan", count: ssp ? 1 : 0,
      status: ssp ? :complete : :absent,
      detail: ssp ? "#{ssp.name} (#{ssp.creation_method})" : "No SSP",
      guide_anchor: "5-do-you-already-have-an-ssp"
    )
  end

  # Typing everything `this-system` is the path of least resistance and costs
  # the ability to say what is inherited, shared or operated — so a single
  # undifferentiated component is reported as PARTIAL, not complete.
  def components
    return absent_without_ssp(:components, COMPONENTS_TITLE, "2-what-makes-up-the-boundary") if ssp.nil?

    all = ssp.ssp_components
    count = all.count
    typed = all.distinct.pluck(:component_type).compact
    with_protocols = all.reject { |c| c.protocols_data.blank? }.size

    status = if count.zero? then :absent
    elsif typed == [ "this-system" ] || with_protocols.zero? then :partial
    else :complete
    end

    Section.new(
      key: :components, title: COMPONENTS_TITLE, count: count, status: status,
      detail: count.zero? ? "No components recorded" :
              "#{count} component(s); types: #{typed.join(', ')}; #{with_protocols} with ports/protocols",
      guide_anchor: "2-what-makes-up-the-boundary"
    )
  end

  # Register before you resolve — a profile resolving over dangling references
  # exports something that cites documents nobody registered.
  def back_matter
    count = BackMatterResource.where(resourceable: boundary).count

    Section.new(
      key: :back_matter, title: "Back-matter documents", count: count,
      status: count.zero? ? :absent : :complete,
      detail: count.zero? ? "No boundary documents registered (diagrams, inventory, PPSM, CRM)" :
                            "#{count} resource(s) registered",
      guide_anchor: "4-which-documents-become-back-matter"
    )
  end

  def leveraged
    count = boundary.leveraged_relationships.count

    Section.new(
      key: :leveraged, title: "Leveraged authorizations", count: count,
      status: count.zero? ? :absent : :complete,
      detail: count.zero? ? "Nothing recorded as leveraged — every control reads as system-specific" :
                            "#{count} leveraged relationship(s)",
      guide_anchor: "6-what-are-you-leveraging"
    )
  end

  def cdefs
    count = boundary.cdef_documents.count

    Section.new(
      key: :cdefs, title: "Component definitions", count: count,
      status: count.zero? ? :absent : :complete,
      detail: count.zero? ? "No CDEFs bound" : "#{count} CDEF(s) bound",
      guide_anchor: "6-what-are-you-leveraging"
    )
  end

  # No `partial` state here, deliberately. The first version had one for
  # "evidence exists but links to no control" — that state CANNOT OCCUR: Evidence
  # validates "Link at least one control — evidence that supports no control
  # cannot be assessed and appears under nothing." The invariant is enforced at
  # the model, so reporting on it would be dead code pretending to be a check.
  def evidence
    count = boundary.evidences.count
    linked = EvidenceControlLink.where(evidence_id: boundary.evidences.select(:id))
                                .select(:evidence_id).distinct.count

    Section.new(
      key: :evidence, title: "Evidence", count: count,
      status: count.zero? ? :absent : :complete,
      detail: count.zero? ? "No evidence uploaded" : "#{count} item(s), #{linked} linked to controls",
      guide_anchor: "9-how-will-you-provide-evidence"
    )
  end

  def scans
    count = boundary.scan_runs.count
    latest = boundary.scan_runs.maximum(:ingested_at)

    Section.new(
      key: :scans, title: "Scan results (HDF)", count: count,
      status: count.zero? ? :absent : :complete,
      detail: count.zero? ? "No scan results ingested" :
                            "#{count} run(s); most recent #{latest&.to_date}",
      guide_anchor: "9-how-will-you-provide-evidence"
    )
  end

  # The honest one. The owner asked for "1 to n environments documented" and
  # SPARC has no environment model at all — no table, and no column on
  # AuthorizationBoundary, SspDocument, SspComponent or CdefDocument. Reporting
  # this as `absent` would blame the boundary for SPARC's gap.
  def environments
    Section.new(
      key: :environments, title: "Environments", count: nil, status: :not_modelled,
      detail: "SPARC does not model environments, so this cannot be reported. " \
              "Record them in document metadata until it does.",
      guide_anchor: "2-what-makes-up-the-boundary"
    )
  end

  REQUIRED_ROLES = %w[system_owner isso authorizing_official].freeze

  # Named once. The first version titled this section "Components" when there was
  # no SSP and "Components, ports and protocols" otherwise — a heading that
  # changes with the data is one a reader cannot search for, and its own spec
  # caught it.
  COMPONENTS_TITLE = "Components, ports and protocols"

  def absent_without_ssp(key, title, anchor)
    Section.new(key: key, title: title, count: 0, status: :absent,
                detail: "No SSP, so nothing is recorded", guide_anchor: anchor)
  end
end
