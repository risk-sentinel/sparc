class SarControlField < ApplicationRecord
  belongs_to :sar_control

  validates :field_name, presence: true

  # What an assessor RECORDS about a control.
  #
  # #1114 — this list is the legacy Test Plan Results SPREADSHEET vocabulary,
  # inherited when `0b04dc25` renamed TPR to SAR "for OSCAL alignment" without
  # remodelling the fields. Owner review pruned it:
  #
  #   custom, custom_name  removed — spreadsheet free-columns with no semantics,
  #                        nothing in OSCAL to carry them, nothing that reads them
  #   custom_author        renamed `assessor`, and defaulted to the signed-in user
  #                        rather than typed. In OSCAL this is an assessment
  #                        actor, not a free-text note
  #   expected_result      removed — 800-53A already STATES the expected result as
  #                        determination statements, and SPARC now stores them
  #                        (SarControlObjective). A human retyping it duplicates
  #                        the catalog and can contradict it
  #   test_text            removed — what to examine is the catalog's
  #                        `assessment-objects`, shown per method under Assessment
  #                        Depth rather than typed per control
  #
  # The COLUMNS are left in place. Existing SARs hold values in them and the
  # Excel importer writes them; dropping the data in the same release as the UI
  # would lose an assessor's work with no way back.
  EDITABLE_FIELDS = %w[
    date
    result
    notes_weakness
    recommended_fix
    assessor
    working_comments
    working_status
  ].freeze

  # Retired from the UI, still readable on documents that carry them (#1114).
  LEGACY_FIELDS = %w[test_text expected_result custom custom_name custom_author].freeze

  RESULT_VALUES = %w[Pass Failed].freeze

  WORKING_STATUS_VALUES = [
    "Final - Not Satisfied",
    "Final Satisfied",
    "Not Satisfied",
    "Not Specified"
  ].freeze

  before_validation :set_editable_flag
  after_save :sync_cached_result, if: -> { field_name == "result" }

  # #716 — controlled vocabularies per editable field, for bulk field-import
  # validation. nil ⇒ free text.
  ALLOWED_VALUES = {
    "result"         => RESULT_VALUES,
    "working_status" => WORKING_STATUS_VALUES
  }.freeze

  def self.allowed_values(field_name)
    ALLOWED_VALUES[field_name.to_s]
  end

  private

  def set_editable_flag
    self.editable = EDITABLE_FIELDS.include?(field_name)
  end

  def sync_cached_result
    sar_control.update_column(:cached_result, field_value)
  end
end
