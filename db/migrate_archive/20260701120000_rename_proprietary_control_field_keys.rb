# frozen_string_literal: true

# Renames the five proprietary-looking SSP control-field keys to neutral,
# OSCAL-aligned names (and the shared SAR `coverage_level`), matching the mapping
# schema change in lib/data_mappings/{ssp,sar}_excel.json. The keys persist as
# `field_name` values, so existing rows must be migrated.
#
# Idempotent + resume-safe: each UPDATE only touches rows still holding the old
# name, so re-running is a no-op. The new names do not pre-exist in the data, and
# neither table has a UNIQUE (control_id, field_name) index, so there is no
# collision. Reversible via `down`.
class RenameProprietaryControlFieldKeys < ActiveRecord::Migration[8.1]
  SSP_RENAMES = {
    "implementation_statement" => "implementation_statement",
    "implementation_summary"  => "implementation_summary",
    "control_application"            => "control_application",
    "coverage_level"            => "coverage_level",
    "control_type"    => "control_type"
  }.freeze

  # SAR shares only coverage_level -> coverage_level.
  SAR_RENAMES = { "coverage_level" => "coverage_level" }.freeze

  def up
    rename_field_names("ssp_control_fields", SSP_RENAMES)
    rename_field_names("sar_control_fields", SAR_RENAMES)
  end

  def down
    rename_field_names("ssp_control_fields", SSP_RENAMES.invert)
    rename_field_names("sar_control_fields", SAR_RENAMES.invert)
  end

  private

  def rename_field_names(table, renames)
    renames.each do |from, to|
      execute(
        "UPDATE #{table} SET field_name = #{quote(to)} WHERE field_name = #{quote(from)}"
      )
    end
  end
end
