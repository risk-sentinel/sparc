# frozen_string_literal: true

# #809 (§5) — decide whether/when an amendment (disposition) is valid.
#
# An amendment is valid only if it is within the **ODP remediation timeline of
# impact**, OR an **active POA&M** addressing the control is still open (indefinite
# validity while the POA&M is active).
#
# The remediation window comes from the boundary's profile (baseline_level) and
# the finding's NIST criticality, resolved via the admin-provisioned
# RemediationTimeline SLA table (with built-in defaults). Measured from the
# control's first-discovered scan.
class AmendmentValidityService
  def initialize(finding_disposition)
    @disp = finding_disposition
    @boundary = finding_disposition.authorization_boundary
  end

  # The instant the amendment stops being valid, or nil when POA&M-backed
  # (valid while the POA&M is active) or when no window can be resolved.
  def valid_until
    return nil if active_poam? # POA&M-backed: valid while the POA&M is open

    first = first_discovered_at
    days = window_days
    return nil if first.nil? || days.nil?

    first + days.days
  end

  def valid?
    active_poam? || ((vu = valid_until) && vu > Time.current)
  end

  private

  # #843 — the two vocabulary mappings moved onto RemediationTimeline, which
  # owns the keys they produce, so the POA&M generator resolves an SLA the same
  # way this does instead of carrying a second copy.
  def window_days
    baseline = RemediationTimeline.normalize_baseline(@boundary&.profile_document&.baseline_level)
    RemediationTimeline.window_days(baseline, criticality)
  end

  def criticality
    RemediationTimeline.normalize_criticality(current_finding&.severity)
  end

  def current_finding
    ScannerFinding.current.find_by(
      authorization_boundary_id: @boundary&.id, control_id: @disp.control_id
    )
  end

  # Earliest time this control was seen (across scan history) — the remediation
  # clock starts at first-discovered.
  def first_discovered_at
    ScannerFinding.where(authorization_boundary_id: @boundary&.id, control_id: @disp.control_id)
                  .minimum(:created_at)
  end

  # Is there an open POA&M on this boundary addressing this control? Heuristic:
  # a POA&M finding whose title/description/target references the control id.
  # (A precise control<->POA&M-item link is a refinement; see #811.)
  def active_poam?
    poam_ids = @boundary&.poam_documents&.ids
    return false if poam_ids.blank?

    cid = @disp.control_id.to_s
    PoamFinding.where(poam_document_id: poam_ids)
               .where("title ILIKE :q OR description ILIKE :q OR target_data::text ILIKE :q", q: "%#{cid}%")
               .exists?
  end
end
