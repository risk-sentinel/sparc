class SspControlField < ApplicationRecord
  belongs_to :ssp_control

  validates :field_name, presence: true

  # Fields editable by users per the System Security Plan (SSP) schema.
  # Order here controls the edit-form render order.
  #
  # #1312 — status, control type (origination), responsible entities and
  # expected completion are answered per statement item now
  # (SspControlStatement), and control application and coverage level are
  # retired: neither is OSCAL's, and each duplicated another field.
  EDITABLE_FIELDS = %w[
    implementation_statement
    implementation_summary
    notes
  ].freeze

  # #1312 — the control-level fields an item now answers for itself, or that
  # are gone. Rows that hold them are KEPT until v1.18.0 so an upgrade can be
  # rolled back; nothing shows, edits or exports them, and
  # SspControlFieldCarryDown has copied each value to the control's items.
  RETIRED_FIELDS = %w[
    status
    control_application
    coverage_level
    control_type
    responsible_entities
    expected_completion
  ].freeze

  NOT_APPLICABLE = "Not Applicable".freeze

  # The retired control-level vocabularies (#1312). Still read: an SSP stored
  # or exported before v1.17.5 carries them, and SspControlFieldCarryDown maps
  # each onto OSCAL's values.
  VALID_STATUSES = [
    "Deferred",
    "Implemented",
    NOT_APPLICABLE,
    "Will Not Implement"
  ].freeze

  CONTROL_APPLICATION_VALUES = [
    "System Specific",
    "Hybrid",
    "Inherited",
    "Provider",
    "Consumer"
  ].freeze

  COVERAGE_LEVEL_VALUES = [
    "Implemented",
    "Configured",
    "Documented",
    NOT_APPLICABLE
  ].freeze

  CONTROL_TYPE_VALUES = [
    "System Specific",
    "Hybrid — partially inherited",
    "Inherited from provider",
    NOT_APPLICABLE
  ].freeze

  # Display order for the view mode (editable fields first, then supplemental).
  # Control-level narratives. An SSP is answered part by part
  # (ssp_control_statements); these are no longer offered for new answers, and
  # one that already holds text is still shown and exported.
  CONTROL_LEVEL_NARRATIVES = %w[implementation_statement implementation_summary].freeze

  FIELD_DISPLAY_ORDER = %w[
    implementation_statement
    implementation_summary
    notes
    inherited_from
    history
    class
    priority
    control_owner
    stated_requirement
  ].freeze

  before_validation :set_editable_flag

  # #716 — controlled vocabularies per editable field, for bulk field-import
  # validation. nil ⇒ free text. Model owns its vocabulary. #1312 — every
  # field with a vocabulary is retired, so none remains.
  ALLOWED_VALUES = {}.freeze

  def self.allowed_values(field_name)
    ALLOWED_VALUES[field_name.to_s]
  end

  private

  def set_editable_flag
    self.editable = EDITABLE_FIELDS.include?(field_name)
  end
end
