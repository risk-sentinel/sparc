# #881 — a URL-addressable identifier for catalog controls.
#
# `/catalog_controls/8842` becomes
# `/control_catalogs/nist-800-53-rev5/controls/ac-19.4.b.1`.
#
# This column stores `ControlId.canonical(control_id)` — the SAME form #852
# established and every OSCAL exporter already writes as `control-id`. It is a
# LOOKUP KEY, not a new identity: nothing outside the routing/lookup path should
# read it, and every existing caller keeps calling ControlId.canonical.
#
# Why store it rather than index an expression: canonicalisation is Ruby, so a
# SQL expression index would mean a second implementation of it. #852 exists
# precisely because a dozen divergent copies of that logic had drifted apart.
#
# Measured against the seeded catalogs (3 catalogs, 49 families, 4054 controls):
# canonical ids collide 0 times within a catalog, and 576 of 4054 differ from
# the stored control_id — exactly the parenthesised statement parts
# (`ac-19.4.(b).(1)` -> `ac-19.4.b.1`).
#
# Uniqueness is scoped to the family, mirroring the existing control_id
# validation. Catalog-level uniqueness is what the routes rely on and is
# implied: a family belongs to exactly one catalog.
#
# Nullable on purpose — the backfill is a deferred data migration
# (20260802140100), so the column is empty between this migration and the
# runner completing. CatalogControl#canonical_identifier falls back to computing
# the value, so URLs resolve throughout that window.
class AddCanonicalIdToCatalogControls < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:catalog_controls, :canonical_id)
      add_column :catalog_controls, :canonical_id, :string
    end

    unless index_exists?(:catalog_controls, [ :control_family_id, :canonical_id ],
                         name: "index_catalog_controls_on_family_and_canonical_id")
      add_index :catalog_controls, [ :control_family_id, :canonical_id ],
                unique: true,
                name: "index_catalog_controls_on_family_and_canonical_id"
    end
  end
end
