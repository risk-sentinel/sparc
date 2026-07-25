# frozen_string_literal: true

# #447 — one control result from an ingested scan (translation state mirroring
# the HDF `controls[]`). Unique per (authorization_boundary, control_id): a fresh
# scan UPDATES the current finding rather than duplicating. The disposition is
# looked up by the same (boundary, control_id) key, so it is independent of which
# scan_run last touched the finding.
class ScannerFinding < ApplicationRecord
  belongs_to :scan_run
  belongs_to :authorization_boundary

  before_validation :assign_uuid_if_blank

  # HDF control statuses (mirrors hdf-cli).
  STATUSES = %w[passed failed skipped error notApplicable].freeze
  SEVERITIES = %w[CRITICAL HIGH MEDIUM LOW INFORMATIONAL].freeze

  validates :control_id, presence: true,
            uniqueness: { scope: :authorization_boundary_id, case_sensitive: true }
  validates :status, presence: true
  validates :uuid, presence: true

  scope :failed, -> { where(status: "failed") }
  scope :for_boundary, ->(boundary) { where(authorization_boundary: boundary) }

  def to_param
    uuid
  end

  # The current triage decision for this finding, if any. Keyed by
  # (boundary, control_id), not by a FK, so it survives re-ingest.
  def disposition
    FindingDisposition.find_by(
      authorization_boundary_id: authorization_boundary_id,
      control_id: control_id
    )
  end

  def dispositioned?
    disposition.present?
  end

  private

  def assign_uuid_if_blank
    self.uuid = SecureRandom.uuid if uuid.blank?
  end
end
