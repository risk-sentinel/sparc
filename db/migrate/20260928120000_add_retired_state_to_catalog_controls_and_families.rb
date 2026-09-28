# frozen_string_literal: true

# #1115 — a catalog entry can be RETIRED without being deleted.
#
# FedRAMP re-keyed its KSI catalog: 10 of SPARC's 54 indicators are renamed in
# place, and the other 44 (with the whole AUTH theme) no longer exist upstream.
# Deleting them is not an option: `CatalogControl has_many :ksi_validations,
# dependent: :destroy`, so a delete would take each boundary's recorded
# assessment with it. They are retired instead — kept, readable as history,
# excluded from the current catalog — and point at the closest successor.
#
#   catalog_controls.retired_at     when the entry left the authoritative source
#   catalog_controls.superseded_by  jsonb array of successor ids (a pointer, not a
#                                   claim that an assessment carries over)
#   control_families.retired_at     a theme that no longer exists (KSI AUTH)
#
# Nullable, no default backfill: nothing is retired until an importer says so.
# Guarded per the Migration Safety Rules, so a partial run can be re-run.
class AddRetiredStateToCatalogControlsAndFamilies < ActiveRecord::Migration[8.1]
  def up
    add_column :catalog_controls, :retired_at, :datetime unless column_exists?(:catalog_controls, :retired_at)
    add_column :catalog_controls, :superseded_by, :jsonb, default: [], null: false unless column_exists?(:catalog_controls, :superseded_by)
    add_index :catalog_controls, :retired_at, if_not_exists: true
    add_column :control_families, :retired_at, :datetime unless column_exists?(:control_families, :retired_at)
  end

  def down
    remove_column :control_families, :retired_at, if_exists: true
    remove_index :catalog_controls, :retired_at, if_exists: true
    remove_column :catalog_controls, :superseded_by, if_exists: true
    remove_column :catalog_controls, :retired_at, if_exists: true
  end
end
