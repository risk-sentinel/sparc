# frozen_string_literal: true

# 1.18.0-rf #1301 — what the boundary page shows above its sections under
# SPARC_NAV_SHELL: one row per document, the latest activity, the facts in the
# About column and what needs attention. Read-only; the controller has
# already admitted the viewer to the boundary.
#
# Each fact reads an existing definition, so the page cannot disagree with
# the screen that fact links to:
#   CDEFs, POA&Ms   BoundaryScopedList, the narrowing the lists use
#   activity        BoundaryActivity, the Boundaries tab's sparklines
#   SSP completion  SspResponseProgress, the SSP list's "Responses answered"
#   baseline        CdefBaselineGapService.baseline_control_ids
#
# NIST SP 800-53 Rev 5:
#   CA-5 Plan of Action and Milestones — overdue items are surfaced.
#   CA-7 Continuous Monitoring — controls with no evidence are counted.
#   AU-6 Audit Record Review — the latest audited change is shown.
class BoundaryHome
  Row = Data.define(:key, :label, :name, :url, :status, :updated_at, :count, :missing)

  def initialize(boundary)
    @boundary = boundary
  end

  attr_reader :boundary

  # The boundary's documents, in OSCAL's order (baseline, SSP, CDEFs, SAP,
  # SAR, POA&M) and then what it leverages. A missing single document links
  # to the screen that attaches one.
  def documents
    [
      single(:profile, "Baseline", boundary.profile_document, nil),
      single(:ssp, "SSP", boundary.ssp_document, attach(:ssp)),
      many(:cdef, "CDEFs", cdefs, BoundaryScopedList.path(:cdef, boundary), nil),
      single(:sap, "SAP", boundary.sap_document, attach(:sap)),
      single(:sar, "SAR", boundary.sar_document, attach(:sar)),
      many(:poam, "POA&Ms", boundary.poam_documents, BoundaryScopedList.path(:poam, boundary), attach(:poam)),
      leveraged
    ]
  end

  def latest_activity = @latest_activity ||= BoundaryActivity.latest(boundary.id).first

  def weekly_activity = @weekly_activity ||= BoundaryActivity.weekly([ boundary.id ]).fetch(boundary.id)

  def overdue_poam_items
    @overdue_poam_items ||= PoamItem.overdue.where(poam_document_id: boundary.poam_documents.select(:id)).count
  end

  # Baseline controls no evidence in this boundary is linked to. nil when the
  # boundary has no baseline (nothing to measure against).
  def controls_without_evidence
    return @controls_without_evidence if defined?(@controls_without_evidence)

    profile = boundary.profile_document
    @controls_without_evidence =
      if profile&.resolved_catalog_json.present?
        required = CdefBaselineGapService.baseline_control_ids(profile).map { ControlId.canonical(_1) }.to_set
        linked = EvidenceControlLink.where(evidence_id: boundary.evidences.select(:id)).distinct.pluck(:control_id)
        (required - linked.map { ControlId.canonical(_1) }).size
      end
  end

  # The SSP's required responses: [done, required], or nil with no SSP.
  def ssp_completion
    return @ssp_completion if defined?(@ssp_completion)

    total = boundary.ssp_document && SspResponseProgress.for(boundary.ssp_document).total
    @ssp_completion = total && [ total.done, total.required ]
  end

  def impact_label
    level = boundary.security_categorization
    level.present? ? SspInformationType.impact_label(level) : nil
  end

  def people_with_role(key)
    boundary.personnel_roster.select { _1.role_key.to_s == key }.map(&:name).compact_blank.uniq
  end

  private

  def cdefs = BoundaryScopedList.narrow(:cdef, CdefDocument.all, boundary.id)

  def attach(type) = Rails.application.routes.url_helpers.attach_document_authorization_boundary_path(boundary, type: type)

  def single(key, label, doc, add_url)
    Row.new(key: key, label: label, name: doc&.name, url: doc || add_url,
            status: (doc.lifecycle_label if doc.respond_to?(:lifecycle_label)),
            updated_at: doc&.updated_at, count: nil, missing: doc.nil?)
  end

  def many(key, label, relation, list_url, add_url)
    count = relation.count
    Row.new(key: key, label: label, name: nil, url: (count.zero? && add_url) ? add_url : list_url,
            status: nil, updated_at: relation.maximum(:updated_at), count: count, missing: count.zero?)
  end

  def leveraged
    count = boundary.leveraging_relationships.count
    Row.new(key: :leveraged, label: "Leveraged", name: nil, url: "#boundary-leveraged",
            status: nil, updated_at: boundary.leveraging_relationships.maximum(:updated_at), count: count, missing: count.zero?)
  end
end
