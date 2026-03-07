class PoamFinding < ApplicationRecord
  belongs_to :poam_document

  has_many :poam_item_findings, dependent: :delete_all
  has_many :poam_items, through: :poam_item_findings
  has_many :poam_finding_observations, dependent: :delete_all
  has_many :poam_observations, through: :poam_finding_observations
  has_many :poam_finding_risks, dependent: :delete_all
  has_many :poam_risks, through: :poam_finding_risks

  validates :uuid, presence: true
end
