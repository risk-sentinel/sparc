# frozen_string_literal: true

# #1252 — OSCAL groups at any depth.
#
# A catalog group may hold groups as well as controls. The import read only each
# top-level group's own `controls`, so a catalog whose controls sit in subgroups
# (NIST's example catalog: `s1` → `s1.1` → `s1.1.1`) imported with none, and
# said nothing. Families stay one level, as every screen expects; what a family
# was imported from is kept beside it:
#
#   control_families.group_data  the top-level group's own fields (id, class,
#                                props, parts, links, params) and its nested
#                                groups' definitions, in file order, without
#                                their controls
#   catalog_controls.group_id    the nested group a row sits in; NULL when it
#                                sits directly in the family's group
#
# Existing rows need no backfill: every catalog imported so far had controls
# only in top-level groups, which is what an empty group_data and a NULL
# group_id describe.
class AddNestedGroupsToCatalogs < ActiveRecord::Migration[8.1]
  def change
    add_column :control_families, :group_data, :jsonb, default: {}, null: false
    add_column :catalog_controls, :group_id, :string
  end
end
