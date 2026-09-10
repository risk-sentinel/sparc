class SapControlObjective < ApplicationRecord
  belongs_to :sap_control

  OBJECTIVE_STATUSES = %w[pending in-progress passing failed not_applicable].freeze

  validates :objective_id, presence: true,
                           uniqueness: { scope: :sap_control_id }
  validates :uuid, presence: true
  validates :status, inclusion: { in: OBJECTIVE_STATUSES }

  # #1114 — NIST's 800-53A tree has CONTAINER nodes above the determination
  # statements: `ac-1_obj`, `ac-1_obj.a`, `ac-1_obj.a.1` carry a label and NO
  # prose, and exist to group the leaves beneath them.
  #
  # A container is not a thing an assessor determines — there is nothing stated
  # to determine — so it is not assessable, and it must not be counted as work.
  # Measured on ac-1: 24 objectives, 7 of them containers, so a FULLY assessed
  # control reported 71% and the progress bar could never reach 100%.
  #
  # Same container-vs-leaf distinction as #1113, where binding a field to a
  # container rendered an empty box.
  def container? = prose.to_s.strip.blank?

  def determinable? = !container?

  scope :determinable, -> { where.not(prose: [ nil, "" ]) }

  scope :failing,         -> { where(status: "failed") }
  scope :passing,         -> { where(status: "passing") }
  scope :in_progress,     -> { where(status: "in-progress") }
  scope :pending,         -> { where(status: "pending") }
  scope :not_applicable,  -> { where(status: "not_applicable") }
end
