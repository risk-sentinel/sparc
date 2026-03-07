class SapControlField < ApplicationRecord
  belongs_to :sap_control

  validates :field_name, presence: true

  EDITABLE_FIELDS = %w[
    assessment_method
    assessment_status
    assessor_name
    objective
    test_case
    notes
    expected_result
  ].freeze

  FIELD_DISPLAY_ORDER = %w[
    objective
    assessment_method
    assessment_status
    assessor_name
    test_case
    expected_result
    implementation_description
    evidence_description
    notes
  ].freeze

  before_validation :set_editable_flag

  private

  def set_editable_flag
    self.editable = EDITABLE_FIELDS.include?(field_name)
  end
end
