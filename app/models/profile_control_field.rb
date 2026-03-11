class ProfileControlField < ApplicationRecord
  belongs_to :profile_control

  validates :field_name, presence: true

  EDITABLE_FIELDS = %w[
    tailoring_notes
    parameter_value
  ].freeze

  FIELD_DISPLAY_ORDER = %w[
    parameter_id
    parameter_value
    parameter_label
    alter_adds
    alter_removes
    tailoring_notes
  ].freeze

  before_validation :set_editable_flag

  private

  def set_editable_flag
    self.editable = EDITABLE_FIELDS.include?(field_name) ||
      (field_name.start_with?("parameter:") && !field_name.start_with?("parameter_label:"))
  end
end
