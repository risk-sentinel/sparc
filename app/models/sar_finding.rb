class SarFinding < ApplicationRecord
  belongs_to :sar_result
  belongs_to :sar_control_objective, optional: true

  has_many :sar_finding_observations, dependent: :delete_all
  has_many :sar_observations, through: :sar_finding_observations
  has_many :sar_finding_risks, dependent: :delete_all
  has_many :sar_risks, through: :sar_finding_risks

  validates :uuid, presence: true
end
