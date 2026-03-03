class SspControlField < ApplicationRecord
  belongs_to :ssp_control

  validates :field_name, presence: true

  # Fields editable by users per the Controls Implementation schema
  EDITABLE_FIELDS = %w[
    private_implementation
    public_implementation
    notes
    status
    expected_completion
    responsible_entities
    type_use_as
    provided_as
    control_origination
  ].freeze

  VALID_STATUSES = [
    "Deferred",
    "Implemented",
    "Not Applicable",
    "Will Not Implement"
  ].freeze

  before_validation :set_editable_flag

  private

  def set_editable_flag
    self.editable = EDITABLE_FIELDS.include?(field_name)
  end
end
