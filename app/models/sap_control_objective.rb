class SapControlObjective < ApplicationRecord
  belongs_to :sap_control

  OBJECTIVE_STATUSES = %w[pending in-progress passing failed not_applicable].freeze

  validates :objective_id, presence: true,
                           uniqueness: { scope: :sap_control_id }
  validates :uuid, presence: true
  validates :status, inclusion: { in: OBJECTIVE_STATUSES }

  scope :failing,         -> { where(status: "failed") }
  scope :passing,         -> { where(status: "passing") }
  scope :in_progress,     -> { where(status: "in-progress") }
  scope :pending,         -> { where(status: "pending") }
  scope :not_applicable,  -> { where(status: "not_applicable") }
end
