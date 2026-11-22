# frozen_string_literal: true

# #1390 — one Ongoing Certification Report a boundary issued (CCM-OCR-AVL):
# its period, the recommendations typed for it, and the document exactly as
# issued, with its SHA-256. Written by FedrampOngoingReportService#issue and
# never changed or deleted.
#
# NIST SP 800-53: CA-7 (continuous monitoring), PM-31, AU-10 (the issued
# document is kept as issued).
class FedrampOngoingReport < ApplicationRecord
  DOCUMENT_TYPE = "ongoing-certification-report"

  belongs_to :authorization_boundary
  belongs_to :issued_by, class_name: "User", optional: true

  validates :period_from, :period_to, :document, :sha256, presence: true
  validate :period_in_order
  before_update { throw :abort }
  before_destroy { throw(:abort) unless destroyed_by_association }

  scope :newest_first, -> { order(period_to: :desc, id: :desc) }

  def to_param = uuid

  private

  def period_in_order
    errors.add(:period_to, "is before the start of the period") if period_from && period_to && period_to < period_from
  end
end
