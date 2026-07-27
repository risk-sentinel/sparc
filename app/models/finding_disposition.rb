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

  before_validation :assign_uuid_if_blank
  before_validation :default_decided_at, on: :create

  # The complete v3.4.0 HDF Amendment override enum (`exception` removed upstream).
  KINDS = %w[
    falsePositive waiver poam vendorDependency inherited riskAdjustment operationalRequirement
  ].freeze

  # How each kind maps to the amended HDF status (used by the export service).
  NOT_APPLICABLE_KINDS = %w[falsePositive waiver inherited].freeze
  FAILED_KINDS = %w[poam vendorDependency riskAdjustment operationalRequirement].freeze

  # Kinds that hold or defer risk on a clock — an expiration is mandatory.
  EXPIRATION_REQUIRED_KINDS = %w[waiver operationalRequirement].freeze

  validates :control_id, presence: true,
            uniqueness: { scope: :authorization_boundary_id, case_sensitive: true }
  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :reason, presence: true
  validates :decided_by, presence: true
  validates :decided_at, presence: true
  validates :uuid, presence: true
  validates :expiration, presence: true, if: :expiration_required?
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
  def hdf_status
    NOT_APPLICABLE_KINDS.include?(kind) ? "notApplicable" : "failed"
  end

  def expiration_required?
    EXPIRATION_REQUIRED_KINDS.include?(kind)
  end

  def expired?
    expiration.present? && expiration <= Time.current
  end

  private

  def assign_uuid_if_blank
    self.uuid = SecureRandom.uuid if uuid.blank?
  end

  def default_decided_at
    self.decided_at ||= Time.current
  end
end
