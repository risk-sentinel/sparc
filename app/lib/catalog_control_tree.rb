# frozen_string_literal: true

# CatalogControlTree — a catalog's OSCAL controls in catalog order, each with
# its parent control (#1252). What profile selection reads for `include-all`,
# `matching` and `with-child-controls`.
#
# Read from the hierarchy imports record (`parent_control_id`, and
# `statement_item` for the item rows an import derives from a statement,
# which are not controls). It does not guess from id shapes, so a catalog whose
# ids are not NIST's (FedRAMP 20x `ksi-auth-01`, NIST's example `s1.1.1`)
# selects as its file says.
#
# NIST 800-53: CM-2.
class CatalogControlTree
  def self.for(catalog)
    new(catalog).pairs
  end

  def initialize(catalog)
    @catalog = catalog
  end

  # @return [Array<Array(String, String|nil)>] [id, parent_id] in catalog order
  def pairs
    CatalogControl.unscoped.joins(:control_family)
                  .where(control_families: { control_catalog_id: @catalog.id }, statement_item: false)
                  .order("control_families.sort_order", "control_families.id",
                         Arel.sql("COALESCE(catalog_controls.sort_id, catalog_controls.control_id)"),
                         "catalog_controls.id")
                  .pluck(:control_id, :parent_control_id)
  end
end
