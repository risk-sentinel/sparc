class PoamItem < ApplicationRecord
  belongs_to :poam_document

  has_many :poam_item_risks, dependent: :delete_all
  has_many :poam_risks, through: :poam_item_risks
  has_many :poam_item_observations, dependent: :delete_all
  has_many :poam_observations, through: :poam_item_observations
  has_many :poam_item_findings, dependent: :delete_all
  has_many :poam_findings, through: :poam_item_findings

  def primary_risk
    poam_risks.order("poam_item_risks.id").first
  end

  def to_hash
    {
      title: title,
      description: description,
      poam_item_uuid: poam_item_uuid,
      risk_status: risk_status,
      risk_level: risk_level,
      likelihood: likelihood,
      impact: impact,
      deadline: deadline,
      row_order: row_order,
      internal_notes: internal_notes,
      closure_evidence: closure_evidence,
      risk_count: poam_risks.size,
      observation_count: poam_observations.size,
      finding_count: poam_findings.size
    }
  end
end
