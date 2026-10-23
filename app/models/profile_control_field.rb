class ProfileControlField < ApplicationRecord
  belongs_to :profile_control

  validates :field_name, presence: true

  # #1270 — `parameter_value` was editable here too: a free-text field on the
  # control Edit screen that no export, resolution or SSP generation read, so
  # anything typed in it went nowhere. Parameter values are tailored per
  # parameter (`parameter:<id>`) on the Profile screen. Stored values are kept.
  EDITABLE_FIELDS = %w[
    tailoring_notes
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
