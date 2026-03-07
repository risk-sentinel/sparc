class PoamRisk < ApplicationRecord
  belongs_to :poam_document

  has_many :poam_remediations, dependent: :delete_all
  has_many :poam_milestones, through: :poam_remediations

  has_many :poam_item_risks, dependent: :delete_all
  has_many :poam_items, through: :poam_item_risks
  has_many :poam_risk_observations, dependent: :delete_all
  has_many :poam_observations, through: :poam_risk_observations
  has_many :poam_finding_risks, dependent: :delete_all
  has_many :poam_findings, through: :poam_finding_risks

  validates :uuid, presence: true

  STATUSES = %w[open investigating remediating deviation-requested deviation-approved closed].freeze
end
