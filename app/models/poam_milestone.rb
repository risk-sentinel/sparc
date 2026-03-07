class PoamMilestone < ApplicationRecord
  belongs_to :poam_remediation

  has_one :poam_risk, through: :poam_remediation

  validates :uuid, presence: true
end
