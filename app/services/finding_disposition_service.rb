# frozen_string_literal: true

require "digest"

# #447 — the triage decision layer. Creates/updates the FindingDisposition for a
# ScannerFinding, enforcing the per-kind linkage rules and the #244 severity
# policy that the static CI translator proved, now against DB records.
#
# Linkage contract (design §4):
#   falsePositive          -> Evidence
#   waiver                 -> Attestation (an Authorizing Official role) + expiration
#   poam / vendorDependency -> PoamFinding
#   inherited              -> AuthorizationBoundary (the upstream/providing system)
#   riskAdjustment         -> RiskAssessment
#   operationalRequirement -> Attestation (an Authorizing Official role) + expiration
#
# Severity policy: CRITICAL findings may not be risk-accepted or downgraded
# (waiver / riskAdjustment / operationalRequirement) — they must be remediated or
# tracked as a POA&M. falsePositive IS allowed on CRITICAL (the scanner may be
# wrong), matching the CI translator's CRITICAL_ALLOWED_DISPOSITIONS.
#
# NIST 800-53: SI-2 (flaw remediation), CA-7 (continuous monitoring),
# RA-3 (risk assessment linkage), AU-10 (signature_hash provenance).
class FindingDispositionService
  class DispositionError < StandardError; end

  # kind => required linked_subject class name.
  LINKAGE = {
    "falsePositive"          => "Evidence",
    "waiver"                 => "Attestation",
    "poam"                   => "PoamFinding",
    "vendorDependency"       => "PoamFinding",
    "inherited"              => "AuthorizationBoundary",
    "riskAdjustment"         => "RiskAssessment",
    "operationalRequirement" => "Attestation"
  }.freeze

  # Attestation-linked kinds require an Authorizing Official attestation.
  AO_ATTESTATION_KINDS = %w[waiver operationalRequirement].freeze

  # #947 — the AO role NAMES, not one hardcoded string.
  #
  # `Attestation#role` used to come from a six-item list of its own in which the
  # AO was spelled `authorizing_official`. That list is gone: the role is now a
  # canonical `Role` name, and the Authorizing Official is seeded as `ao` (with
  # `agency_ao` for the agency-specific authorizer). Left as it was, this check
  # would have refused EVERY newly recorded AO attestation — silently blocking
  # waivers and operational-requirement dispositions, on a rule whose whole
  # point is that only an AO may accept residual risk.
  #
  # `authorizing_official` is kept so attestations recorded under the old
  # vocabulary keep satisfying dispositions already linked to them. Accepting a
  # historical spelling is not the same as accepting a new unverified claim —
  # `Attestation` validates the latter.
  AO_ROLE_NAMES = %w[ao agency_ao authorizing_official].freeze

  # Not permitted on CRITICAL findings (no risk acceptance / downgrade).
  CRITICAL_BANNED_KINDS = %w[waiver riskAdjustment operationalRequirement].freeze

  # Whitelist of polymorphic linkable types (prevents arbitrary class lookup).
  RESOLVABLE_TYPES = %w[Evidence Attestation PoamFinding AuthorizationBoundary RiskAssessment].freeze

  def initialize(finding)
    @finding = finding
    @boundary = finding.authorization_boundary
  end

  # Resolve a polymorphic linked subject from a whitelisted (type, id) pair.
  # Returns nil when either is blank; raises on an unknown type or missing record.
  def self.resolve_subject(type, id)
    return nil if type.blank? || id.blank?
    raise DispositionError, "Unsupported linked_subject_type '#{type}'" unless RESOLVABLE_TYPES.include?(type)

    type.constantize.find(id)
  rescue ActiveRecord::RecordNotFound
    raise DispositionError, "Linked #{type} ##{id} not found"
  end

  def upsert(kind:, reason:, decided_by:, linked_subject: nil, expiration: nil)
    validate_kind!(kind)
    validate_severity!(kind)
    validate_linkage!(kind, linked_subject)

    disposition = FindingDisposition.find_or_initialize_by(
      authorization_boundary_id: @boundary.id, control_id: @finding.control_id
    )
    disposition.assign_attributes(
      kind: kind, reason: reason, decided_by: decided_by,
      linked_subject: linked_subject, expiration: expiration, decided_at: Time.current
    )
    # Editing a disposition resets its approval; it must be re-approved.
    disposition.assign_attributes(approval_status: "draft", approved_by: nil, approved_at: nil)
    disposition.valid_until = AmendmentValidityService.new(disposition).valid_until # #809 ODP window
    disposition.signature_hash = signature_for(disposition)
    disposition.save!
    disposition
  rescue ActiveRecord::RecordInvalid => e
    raise DispositionError, e.record.errors.full_messages.to_sentence
  end

  # #809 — approve/reject the amendment. Approver is bound into the signature.
  def self.approve(disposition, approved_by:)
    disposition.update!(
      approval_status: "approved", approved_by: approved_by, approved_at: Time.current
    )
    disposition
  end

  def self.reject(disposition, approved_by:)
    disposition.update!(
      approval_status: "rejected", approved_by: approved_by, approved_at: Time.current
    )
    disposition
  end

  private

  def validate_kind!(kind)
    return if FindingDisposition::KINDS.include?(kind)

    raise DispositionError, "Unknown override kind '#{kind}'"
  end

  def validate_severity!(kind)
    return unless @finding.severity.to_s.upcase == "CRITICAL"
    return unless CRITICAL_BANNED_KINDS.include?(kind)

    raise DispositionError,
          "CRITICAL findings cannot be dispositioned as '#{kind}' — remediate or track as a POA&M"
  end

  def validate_linkage!(kind, subject)
    expected = LINKAGE.fetch(kind)
    raise DispositionError, "#{kind} requires a linked #{expected}" if subject.nil?

    unless subject.class.name == expected
      raise DispositionError, "#{kind} must link a #{expected}, got #{subject.class.name}"
    end

    if AO_ATTESTATION_KINDS.include?(kind) && AO_ROLE_NAMES.exclude?(subject.role.to_s)
      raise DispositionError,
            "#{kind} requires an Attestation by an Authorizing Official " \
            "(role: #{AO_ROLE_NAMES.join(' or ')}), got #{subject.role.inspect}"
    end
  end

  # Provenance over the tenant-supplied inputs SPARC binds (it does not author).
  def signature_for(disposition)
    payload = [
      disposition.authorization_boundary_id, disposition.control_id, disposition.kind,
      disposition.reason, disposition.linked_subject_type, disposition.linked_subject_id,
      disposition.expiration&.utc&.iso8601, disposition.decided_by
    ].join("|")
    Digest::SHA256.hexdigest(payload)
  end
end
