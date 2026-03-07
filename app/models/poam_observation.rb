class PoamObservation < ApplicationRecord
  belongs_to :poam_document

  has_many :poam_item_observations, dependent: :delete_all
  has_many :poam_items, through: :poam_item_observations
  has_many :poam_risk_observations, dependent: :delete_all
  has_many :poam_risks, through: :poam_risk_observations
  has_many :poam_finding_observations, dependent: :delete_all
  has_many :poam_findings, through: :poam_finding_observations

  validates :uuid, presence: true
end
