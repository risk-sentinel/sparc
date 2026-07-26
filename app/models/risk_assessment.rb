# frozen_string_literal: true

# #447 — link target for the `riskAdjustment` HDF override. A provenance-bearing
# record that a finding's severity was downgraded, with the original/adjusted
# severities and rationale. `adjusted_severity` must rank strictly below
# `original_severity`.
class RiskAssessment < ApplicationRecord
  include Sluggable
  sluggable_source :title

  belongs_to :authorization_boundary
  belongs_to :evidence, optional: true
  has_many :finding_dispositions, as: :linked_subject, dependent: :nullify

  before_validation :assign_uuid_if_blank

  SEVERITIES = %w[CRITICAL HIGH MEDIUM LOW INFORMATIONAL].freeze
  # Ordinal ranking so "adjusted must be lower than original" is comparable.
  SEVERITY_RANK = { "INFORMATIONAL" => 0, "LOW" => 1, "MEDIUM" => 2, "HIGH" => 3, "CRITICAL" => 4 }.freeze

  validates :title, presence: true
  validates :original_severity, presence: true, inclusion: { in: SEVERITIES }
  validates :adjusted_severity, presence: true, inclusion: { in: SEVERITIES }
  validates :rationale, presence: true
  validates :assessed_by, presence: true
  validates :assessed_at, presence: true
  validates :uuid, presence: true
  validate :adjusted_below_original

  private

  def assign_uuid_if_blank
    self.uuid = SecureRandom.uuid if uuid.blank?
  end

  def adjusted_below_original
    return if original_severity.blank? || adjusted_severity.blank?

    original_rank = SEVERITY_RANK[original_severity]
    adjusted_rank = SEVERITY_RANK[adjusted_severity]
    return if original_rank.nil? || adjusted_rank.nil? # inclusion validation reports these

    return if adjusted_rank < original_rank

    errors.add(:adjusted_severity, "must be lower than original_severity")
  end
end
