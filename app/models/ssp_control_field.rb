class SspControlField < ApplicationRecord
  belongs_to :ssp_control

  validates :field_name, presence: true

  # Fields editable by users per the System Security Plan (SSP) schema.
  # Order here controls the edit-form render order.
  EDITABLE_FIELDS = %w[
    status
    type_use_as
    provided_as
    control_origination
    responsible_entities
    private_implementation
    public_implementation
    expected_completion
    notes,
  ].freeze

  VALID_STATUSES = [
    "Deferred",
    "Implemented",
    "Not Applicable",
    "Will Not Implement"
  ].freeze

  TYPE_USE_AS_VALUES = [
    "System Specific",
    "Hybrid",
    "Inherited",
    "Provider",
    "Consumer"
  ].freeze

  PROVIDED_AS_VALUES = [
    "Implemented",
    "Configured",
    "Documented",
    "Not Applicable"
  ].freeze

  CONTROL_ORIGINATION_VALUES = [
    "System Specific",
    "Hybrid — partially inherited",
    "Inherited from provider",
    "Not Applicable"
  ].freeze

  # Display order for the view mode (editable fields first, then supplemental).
  FIELD_DISPLAY_ORDER = %w[
    status
    type_use_as
    provided_as
    control_origination
    responsible_entities
    private_implementation
    public_implementation
    expected_completion
    notes
    inherited_from
    history
    class
    priority
    control_owner
    stated_requirement,
  ].freeze

  before_validation :set_editable_flag

  private

  def set_editable_flag
    self.editable = EDITABLE_FIELDS.include?(field_name)
  end
end
