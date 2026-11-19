# frozen_string_literal: true

# #447 — the human triage decision SPARC translates into an HDF Amendment
# override. One active disposition per (authorization_boundary, control_id).
# `kind` is one of the v3.4.0 HDF override types; `linked_subject` is the
# justifying artefact appropriate to the kind. This model carries the STRUCTURAL
# rules (kind enum, expiration-required, uniqueness); the richer linkage rules
# (falsePositive needs Evidence, waiver needs an AO Attestation, etc.) are
# enforced by the disposition service (C3) so the model stays cheap to construct
# in tests and other flows.
class FindingDisposition < ApplicationRecord
  belongs_to :authorization_boundary
  belongs_to :linked_subject, polymorphic: true, optional: true
  # #1034 — the identities separation of duties is enforced on. `decided_by` and
  # `approved_by` remain the human-readable provenance the export and signature
  # hash use; these are for comparison, which names cannot do reliably.
  belongs_to :decided_by_user,  class_name: "User", optional: true
  belongs_to :approved_by_user, class_name: "User", optional: true

  before_validation :assign_uuid_if_blank
  before_validation :default_decided_at, on: :create

  # #1368 — the kinds and how each is said in HDF and NIST OSCAL live in
  # DispositionVocabulary, the one definition. `attestation` is HDF's;
  # `vendorDependency` is an HDF POA&M type, exported as a `poam` override.
  KINDS = DispositionVocabulary::KINDS

  # The amended HDF status of each kind (DispositionVocabulary's hdf_status;
  # a kind whose override carries no status leaves the finding failed).
  NOT_APPLICABLE_KINDS = DispositionVocabulary::MAPPINGS.select { |_, m| m.hdf_status == "notApplicable" }.keys.freeze
  PASSED_KINDS = DispositionVocabulary::MAPPINGS.select { |_, m| m.hdf_status == "passed" }.keys.freeze
  FAILED_KINDS = (KINDS - NOT_APPLICABLE_KINDS - PASSED_KINDS).freeze

  # Kinds that hold or defer risk on a clock. Historically the ONLY kinds that
  # required an expiration; every kind requires one now (see the validation
  # below), so this survives to say which ones a reader would expect it of
  # anyway, and is what the UI copy leans on.
  EXPIRATION_REQUIRED_KINDS = %w[waiver operationalRequirement].freeze

  # No disposition parks a finding for longer than this without a human looking
  # at it again. A disposition is a decision taken against a state of the world;
  # a year later the package has moved, the CVE may be fixed, and the reasoning
  # may not hold. An expiry further out than this is indistinguishable from
  # "never re-examined".
  #
  # Anchored on `decided_at` rather than now, so the clock runs from when the
  # decision was actually taken. Re-deciding is what resets it — editing the
  # date alone does not.
  MAX_EXPIRATION_WINDOW = 1.year

  validates :control_id, presence: true,
            uniqueness: { scope: :authorization_boundary_id, case_sensitive: true }
  validates :kind, presence: true, inclusion: { in: KINDS }
  # #1368 — a riskAdjustment re-rates the finding's impact and changes nothing
  # else: hdf-cli 3.8.0 requires the new impact (0.0–1.0) on that override and
  # refuses a status. Every other kind leaves impact alone, so carrying one
  # there would be a value nothing reads.
  validates :adjusted_impact, presence: true,
            numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: 1 },
            if: :risk_adjustment?
  validates :adjusted_impact, absence: { message: "is only for a riskAdjustment" }, unless: :risk_adjustment?
  # #1368 — NIST OSCAL v1.2.3's vocabulary for the POA&M risk this disposition
  # becomes. Required when a disposition is decided (FindingDispositionService);
  # checked here only for being NIST's, so a row decided before these existed
  # can still be approved, and is refused at POA&M export instead.
  validates :nist_risk_prop, inclusion: { in: DispositionVocabulary::RISK_PROPS }, allow_nil: true
  validates :nist_risk_status, inclusion: { in: DispositionVocabulary::RISK_STATUSES }, allow_nil: true
  validates :nist_response_lifecycle, inclusion: { in: DispositionVocabulary::RESPONSE_LIFECYCLES }, allow_nil: true
  validates :nist_facet_state, inclusion: { in: DispositionVocabulary::FACET_STATES }, allow_nil: true
  # NIST SP 800-30 Rev. 1's five levels; the risk level is derived (Table I-2).
  validates :nist_likelihood, :nist_impact, inclusion: { in: DispositionVocabulary::LEVELS }, allow_nil: true
  # A falsePositive is NIST's `false-positive` risk, and only it is.
  validate :false_positive_prop_matches_kind
  validates :reason, presence: true
  validates :decided_by, presence: true
  validates :decided_at, presence: true
  validates :uuid, presence: true
  # EVERY kind, not only the clock kinds.
  #
  # This was conditional until the hdf-cli 3.7.0 pin, which requires an
  # `expiresAt` on every amendment override — measured across all seven kinds,
  # with `null` and `""` both rejected. A disposition without one therefore
  # cannot be exported at all, and SPARC refuses to invent a date rather than
  # write one nobody chose into signed evidence.
  #
  # Enforcing it HERE rather than in each surface is what keeps the UI, the API
  # and the exporter saying the same thing. The alternative — a check in the
  # form, another in the controller, another in the service — is three rules
  # that drift, and the drift shows up as a disposition someone recorded months
  # ago that turns out to be unexportable.
  validates :expiration, presence: true
  validate :expiration_within_review_window
  # #809 — amendment approval flow (creator = decided_by; approver = approved_by).
  validates :approval_status, inclusion: { in: %w[draft approved rejected] }

  APPROVAL_STATUSES = %w[draft approved rejected].freeze

  scope :active, -> { where("expiration IS NULL OR expiration > ?", Time.current) }
  scope :approved, -> { where(approval_status: "approved") }

  def to_param
    uuid
  end

  def approved? = approval_status == "approved"

  # #809 — the amendment is applied only when approved AND still in force. Two
  # independent clocks can stop it, and BOTH must be checked here: `expiration`
  # is the decision's own expiry (mandatory on waiver / operationalRequirement),
  # while `valid_until` is the computed ODP remediation window (nil when an
  # active POA&M backs it). The export path filters expiration via the `active`
  # scope; aggregation and packaging come through here, so omitting `expired?`
  # would let a lapsed waiver keep suppressing its finding and silently skip
  # opening the POA&M item it should have opened.
  def applicable?
    approved? && !expired? && (valid_until.nil? || valid_until > Time.current)
  end

  # The HDF status this disposition amends the finding to.
  def risk_adjustment?
    kind == "riskAdjustment"
  end

  def hdf_status
    DispositionVocabulary.for(kind).hdf_status || "failed"
  end

  # The NIST fields a POA&M export needs that this disposition lacks.
  def missing_nist_fields
    NIST_FIELDS.select { |field| public_send(field).blank? }
  end

  NIST_FIELDS = %i[
    nist_risk_prop nist_risk_status nist_response_lifecycle nist_facet_state nist_likelihood nist_impact
  ].freeze

  # SP 800-30 Rev. 1 Table I-2: the level of risk from likelihood and impact.
  def nist_risk_level
    return if nist_likelihood.blank? || nist_impact.blank?

    DispositionVocabulary.risk_level(nist_likelihood, nist_impact)
  end

  # Kept for callers that ask whether a kind is one a reviewer would EXPECT to
  # carry a clock. It no longer gates the presence validation — every kind does.
  def expiration_required?
    EXPIRATION_REQUIRED_KINDS.include?(kind)
  end

  # The review window, enforced. See MAX_EXPIRATION_WINDOW.
  def expiration_within_review_window
    return if expiration.blank?

    anchor = decided_at || created_at || Time.current
    limit  = anchor + MAX_EXPIRATION_WINDOW
    return if expiration <= limit

    errors.add(:expiration,
               "must be within #{MAX_EXPIRATION_WINDOW.inspect} of the decision " \
               "(#{anchor.to_date} -> #{limit.to_date}); a longer deferral has to be " \
               "re-decided rather than extended")
  end

  def expired?
    expiration.present? && expiration <= Time.current
  end

  private

  def false_positive_prop_matches_kind
    return if nist_risk_prop.blank?
    return if (kind == "falsePositive") == (nist_risk_prop == "false-positive")

    if kind == "falsePositive"
      errors.add(:nist_risk_prop, "must be false-positive for a falsePositive")
    else
      errors.add(:nist_risk_prop, "false-positive is only for a falsePositive")
    end
  end

  def assign_uuid_if_blank
    self.uuid = SecureRandom.uuid if uuid.blank?
  end

  def default_decided_at
    self.decided_at ||= Time.current
  end
end
