class SarFinding < ApplicationRecord
  belongs_to :sar_result
  belongs_to :sar_control_objective, optional: true
  # #393: optional link to a specific SSP implementation statement
  # (the implementation this finding is about). Set on import when the
  # OSCAL target.target-id matches a known SSP statement.
  belongs_to :ssp_control_statement, optional: true

  has_many :sar_finding_observations, dependent: :delete_all
  has_many :sar_observations, through: :sar_finding_observations
  has_many :sar_finding_risks, dependent: :delete_all
  has_many :sar_risks, through: :sar_finding_risks

  validates :uuid, presence: true
end
