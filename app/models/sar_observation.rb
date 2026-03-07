class SarObservation < ApplicationRecord
  belongs_to :sar_result

  has_many :sar_finding_observations, dependent: :delete_all
  has_many :sar_findings, through: :sar_finding_observations
  has_many :sar_risk_observations, dependent: :delete_all
  has_many :sar_risks, through: :sar_risk_observations

  validates :uuid, presence: true
end
