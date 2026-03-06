class SarControlField < ApplicationRecord
  belongs_to :sar_control

  validates :field_name, presence: true

  # Fields editable by users per the Test Plan Results schema
  EDITABLE_FIELDS = %w[
    date
    result
    notes_weakness
    recommended_fix
    test_text
    expected_result
    custom
    custom_name
    custom_author
    working_comments
    working_status
  ].freeze

  RESULT_VALUES = %w[Pass Failed].freeze

  WORKING_STATUS_VALUES = [
    "Final - Not Satisfied",
    "Final Satisfied",
    "Not Satisfied",
    "Not Specified"
  ].freeze

  before_validation :set_editable_flag
  after_save :sync_cached_result, if: -> { field_name == "result" }

  private

  def set_editable_flag
    self.editable = EDITABLE_FIELDS.include?(field_name)
  end

  def sync_cached_result
    sar_control.update_column(:cached_result, field_value)
  end
end
