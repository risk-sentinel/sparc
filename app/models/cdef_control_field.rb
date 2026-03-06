class CdefControlField < ApplicationRecord
  belongs_to :cdef_control

  validates :field_name, presence: true

  EDITABLE_FIELDS = %w[
    notes
    status_override
    implementation_narrative
  ].freeze

  FIELD_DISPLAY_ORDER = %w[
    description
    fix_text
    check_content
    check_system
    severity
    cci_refs
    nist_controls
    rationale
    notes
    status_override
    implementation_narrative
  ].freeze

  SEVERITY_VALUES = %w[high medium low info].freeze

  before_validation :set_editable_flag

  private

  def set_editable_flag
    self.editable = EDITABLE_FIELDS.include?(field_name)
  end
end
