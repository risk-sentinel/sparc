# frozen_string_literal: true

# #809 (D3) — admin-provisioned remediation SLA: how many days a team has to
# remediate, keyed by the profile baseline level and the finding's NIST
# criticality. Used as the fallback for amendment-validity when the boundary's
# profile carries no ODP remediation value for the control.
class RemediationTimeline < ApplicationRecord
  BASELINE_LEVELS = %w[Low Moderate High].freeze
  CRITICALITIES   = %w[Critical High Moderate Low Informational Unknown].freeze

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
