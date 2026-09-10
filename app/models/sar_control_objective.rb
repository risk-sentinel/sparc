class SarControlObjective < ApplicationRecord
  belongs_to :sar_control
  has_many :sar_findings, dependent: :nullify

  OBJECTIVE_STATUSES = %w[pending in-progress passing failed not_applicable].freeze

  validates :objective_id, presence: true,
                           uniqueness: { scope: :sar_control_id }
  validates :uuid, presence: true
  validates :status, inclusion: { in: OBJECTIVE_STATUSES }

  scope :failing,         -> { where(status: "failed") }
  scope :passing,         -> { where(status: "passing") }
  scope :in_progress,     -> { where(status: "in-progress") }
  scope :pending,         -> { where(status: "pending") }
  scope :not_applicable,  -> { where(status: "not_applicable") }

  # #1114 — the OSCAL determination for this objective.
  #
  # An assessment result is, in NIST's model, a finding whose `target` names an
  # `objective-id` and whose `status.state` is one of exactly two values:
  #
  #   oscal_assessment-results_schema v1.2.2
  #     finding.target          REQUIRED type, target-id, status
  #     finding.target.type     enum: statement-id | objective-id
  #     finding.target.status   REQUIRED state
  #     status.state            enum: satisfied | not-satisfied
  #
  # SPARC's stored vocabulary is a WORKFLOW ladder — pending, in-progress,
  # passing, failed, not_applicable — which the format has no equivalent for and
  # which an assessor legitimately needs: "not yet assessed" is not a
  # determination. The two are kept apart rather than one being forced into the
  # other. This maps the workflow state onto the determination NIST allows.
  #
  # Returns nil where no determination has been made. That matters: OSCAL has no
  # "unknown" state for a finding target, so an unassessed objective must produce
  # NO finding rather than a finding asserting it is satisfied. Emitting one
  # would be a false claim of assurance, which is the worst thing an assessment
  # artifact can do.
  OSCAL_STATE = {
    "passing"        => "satisfied",
    "failed"         => "not-satisfied",
    "not_applicable" => nil,
    "pending"        => nil,
    "in-progress"    => nil
  }.freeze

  def oscal_state = OSCAL_STATE[status.to_s]

  def determined? = oscal_state.present?

  scope :determined, -> { where(status: %w[passing failed]) }
end
