class SarRisk < ApplicationRecord
  belongs_to :sar_result

  has_many :sar_risk_observations, dependent: :delete_all
  has_many :sar_observations, through: :sar_risk_observations
  has_many :sar_finding_risks, dependent: :delete_all
  has_many :sar_findings, through: :sar_finding_risks

  validates :uuid, presence: true

  STATUSES = %w[open investigating remediating deviation-requested deviation-approved closed].freeze
end
