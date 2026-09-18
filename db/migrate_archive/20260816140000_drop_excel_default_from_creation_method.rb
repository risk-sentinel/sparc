# #946 — stop every document that does not name its origin from claiming a
# spreadsheet.
#
# `creation_method` defaulted to `'excel'` at the column on both
# `ssp_documents` and `sar_documents`. Every creation path that sets it
# explicitly — wizard, profile, ssp, oscal_import — was fine, but anything that
# did not silently recorded a spreadsheet import that never happened. The
# seeded demo SARs are the visible case: `creation_method: "excel"` beside
# `file_type: "json"` and no `original_filename` at all, three fields
# describing three different origins for one document.
#
# The one path that genuinely relied on the default was an .xlsx upload, which
# skipped the assignment precisely because the default already said "excel".
# `FileUploadable` now states it, so the default has nothing left to do.
#
# Existing rows are untouched: a column default applies only to new inserts,
# and rewriting historical provenance would be the same error in the opposite
# direction — this migration removes a claim SPARC was making, it does not
# withdraw one an operator made.
class DropExcelDefaultFromCreationMethod < ActiveRecord::Migration[8.1]
  TABLES = %i[ssp_documents sar_documents].freeze

  def up
    TABLES.each do |table|
      next unless column_exists?(table, :creation_method)

      change_column_default table, :creation_method, from: "excel", to: nil
    end
  end

  def down
    TABLES.each do |table|
      next unless column_exists?(table, :creation_method)

      change_column_default table, :creation_method, from: nil, to: "excel"
    end
  end
end
