# frozen_string_literal: true

# #1252 — which catalog_controls rows are OSCAL controls, and which control
# each sits under.
#
# The table holds controls and the statement-item rows an import derives
# (`ac-1a`, `ac-1a.1`), with nothing recording which is which or any control's
# parent. Every reader inferred both from NIST's id shape, so a catalog with
# other ids (FedRAMP 20x `ksi-auth-01`, NIST's own example `s1.1.1`) exported
# no controls and could not be selected from by include-all, matching or
# with-child-controls. Imports now record the tree they walk; existing rows are
# backfilled here by CatalogHierarchyBackfill (a few thousand rows, so inline).
class AddHierarchyToCatalogControls < ActiveRecord::Migration[8.1]
  def up
    add_column :catalog_controls, :parent_control_id, :string unless column_exists?(:catalog_controls, :parent_control_id)
    add_column :catalog_controls, :statement_item, :boolean, default: false, null: false unless column_exists?(:catalog_controls, :statement_item)
    add_index :catalog_controls, %i[control_family_id parent_control_id], if_not_exists: true

    CatalogControl.reset_column_information
    CatalogHierarchyBackfill.run.each do |counts|
      say "catalog #{counts[:catalog_id]}: #{counts[:controls]} controls (#{counts[:with_parent]} nested), " \
          "#{counts[:items_from_parts]} statement items from stored parts, #{counts[:items_from_ids]} from ids"
    end
  end

  def down
    remove_index :catalog_controls, %i[control_family_id parent_control_id], if_exists: true
    remove_column :catalog_controls, :statement_item, if_exists: true
    remove_column :catalog_controls, :parent_control_id, if_exists: true
  end
end
