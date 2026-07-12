class CdefControlField < ApplicationRecord
  belongs_to :cdef_control

  validates :field_name, presence: true

  EDITABLE_FIELDS = %w[
    notes
    status_override
    implementation_narrative
    implementation_status
    control_origin
    responsible_roles
    set_parameters
  ].freeze

  FIELD_DISPLAY_ORDER = %w[
    description
    fix_text
    check_content
    check_system
    severity
    baseline_priority
    implementation_status
    control_origin
    responsible_roles
    cci_refs
    nist_controls
    rationale
    set_parameters
    notes
    status_override
    implementation_narrative
  ].freeze

  SEVERITY_VALUES = %w[high medium low info].freeze

  # OSCAL-compliant implementation status values
  IMPLEMENTATION_STATUS_VALUES = %w[
    implemented
    partial
    planned
    alternative
    not-applicable
  ].freeze

  # OSCAL-compliant control origin values
  CONTROL_ORIGIN_VALUES = %w[
    system-specific
    inherited
    shared
  ].freeze

  # Human-readable labels for select dropdowns
  IMPLEMENTATION_STATUS_LABELS = {
    "implemented"    => "Implemented",
    "partial"        => "Partially Implemented",
    "planned"        => "Planned",
    "alternative"    => "Alternative Implementation",
    "not-applicable" => "Not Applicable"
  }.freeze

  CONTROL_ORIGIN_LABELS = {
    "system-specific" => "System-Specific",
    "inherited"       => "Inherited",
    "shared"          => "Shared"
  }.freeze

  before_validation :set_editable_flag

  # Returns true if this field type uses a dropdown selector
  def select_field?
    %w[implementation_status control_origin].include?(field_name)
  end

  # Returns the valid options for select fields
  def select_options
    case field_name
    when "implementation_status" then IMPLEMENTATION_STATUS_LABELS.to_a
    when "control_origin"        then CONTROL_ORIGIN_LABELS.to_a
    else nil # non-select fields have no options
    end
  end

  private

  def set_editable_flag
    self.editable = EDITABLE_FIELDS.include?(field_name)
  end
end
