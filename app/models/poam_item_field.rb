class PoamItemField < ApplicationRecord
  belongs_to :poam_item

  validates :field_name, presence: true

  EDITABLE_FIELDS = %w[
    risk_status
    remediation_description
    milestone_title
    milestone_date
    internal_notes
    closure_evidence
  ].freeze

  FIELD_DISPLAY_ORDER = %w[
    risk_title
    risk_statement
    remediation_lifecycle
    remediation_title
    remediation_description
    milestone_title
    milestone_date
    observation_title
    observation_description
    mitigating_factors
    internal_notes
    closure_evidence
  ].freeze

  before_validation :set_editable_flag

  private

  def set_editable_flag
    self.editable = EDITABLE_FIELDS.include?(field_name)
  end
end
