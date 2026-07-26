# frozen_string_literal: true

# #447/#811 — one control result from a scan. Findings are per-scan_run rows
# (history), with exactly one CURRENT finding per (boundary, control_id) — enforced
# by a partial unique index — so prior scans are retained for N-vs-N-1 re-occurrence
# diffing (carry-forward / re_failed / expired / drift). The disposition is looked
# up by the (boundary, control_id) key, independent of which scan_run touched it.
class ScannerFinding < ApplicationRecord
  belongs_to :scan_run
  belongs_to :authorization_boundary
  belongs_to :cdef_document, optional: true # #811 — resolved target/CDEF

  before_validation :assign_uuid_if_blank

  # HDF control statuses (mirrors hdf-cli).
  STATUSES = %w[passed failed skipped error notApplicable].freeze
  SEVERITIES = %w[CRITICAL HIGH MEDIUM LOW INFORMATIONAL].freeze

  # #811 — re-occurrence lifecycle (distinct from the raw HDF `status`).
  LIFECYCLE_STATUSES = %w[new carried_forward re_failed expired superseded].freeze

  validates :control_id, presence: true
  # Only ONE current finding per (boundary, control_id); history rows are exempt
  # (the uniqueness check compares against current rows only).
  validates :control_id,
            uniqueness: { scope: :authorization_boundary_id, case_sensitive: true,
                          conditions: -> { where(current: true) } },
            if: :current?
  validates :status, presence: true
  validates :lifecycle_status, inclusion: { in: LIFECYCLE_STATUSES }
  validates :uuid, presence: true

  scope :failed, -> { where(status: "failed") }
  scope :current, -> { where(current: true) }
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
