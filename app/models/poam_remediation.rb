class PoamRemediation < ApplicationRecord
  belongs_to :poam_risk

  has_many :poam_milestones, dependent: :delete_all

  validates :uuid, presence: true
end
