# frozen_string_literal: true

# #809 (D3) — admin-provisioned remediation SLA: how many days a team has to
# remediate, keyed by the profile baseline level and the finding's NIST
# criticality. Used as the fallback for amendment-validity when the boundary's
# profile carries no ODP remediation value for the control.
class RemediationTimeline < ApplicationRecord
  BASELINE_LEVELS = %w[Low Moderate High].freeze
  CRITICALITIES   = %w[Critical High Moderate Low Informational Unknown].freeze

  # Translations INTO this table's vocabulary. They live here, with the keys
  # they produce, rather than in each caller — #843 needed the same two
  # mappings AmendmentValidityService already had, and #852 is an open issue
  # about exactly this failure mode (a dozen copies of a normalizer that drift
  # apart). One copy, used by both.
  BASELINE_NORMALIZE = { "low" => "Low", "moderate" => "Moderate", "high" => "High" }.freeze

  # Scanner/assessment severity vocabularies use MEDIUM where the SLA table
  # says Moderate. Anything unrecognised is "Unknown", which has a window of
  # its own rather than being dropped.
  SEVERITY_TO_CRITICALITY = {
    "CRITICAL" => "Critical", "HIGH" => "High", "MEDIUM" => "Moderate",
    "MODERATE" => "Moderate", "LOW" => "Low", "INFORMATIONAL" => "Informational",
    "INFO" => "Informational"
  }.freeze

  DEFAULT_BASELINE = "Moderate"

  def self.normalize_baseline(value)
    BASELINE_NORMALIZE[value.to_s.strip.downcase] || DEFAULT_BASELINE
  end

  def self.normalize_criticality(value)
    SEVERITY_TO_CRITICALITY.fetch(value.to_s.strip.upcase, "Unknown")
  end

  validates :baseline_level, presence: true, inclusion: { in: BASELINE_LEVELS }
  validates :criticality, presence: true, inclusion: { in: CRITICALITIES }
  validates :days, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :baseline_level, uniqueness: { scope: :criticality }

  # Sensible default windows (days) — seeded, admin-editable. Higher-impact
  # baselines and higher criticalities get shorter windows.
  DEFAULTS = {
    "Low"      => { "Critical" => 30, "High" => 30, "Moderate" => 90, "Low" => 180, "Informational" => 365, "Unknown" => 90 },
    "Moderate" => { "Critical" => 15, "High" => 30, "Moderate" => 60, "Low" => 120, "Informational" => 180, "Unknown" => 60 },
    "High"     => { "Critical" => 7,  "High" => 15, "Moderate" => 30, "Low" => 60,  "Informational" => 90,  "Unknown" => 30 }
  }.freeze

  # Resolve the SLA window: the provisioned row, else the built-in default.
  def self.window_days(baseline_level, criticality)
    find_by(baseline_level: baseline_level, criticality: criticality)&.days ||
      DEFAULTS.dig(baseline_level.to_s, criticality.to_s)
  end
end
