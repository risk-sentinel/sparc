# frozen_string_literal: true

# CatalogControlTree — a catalog's OSCAL controls in catalog order, each with
# its parent control (#1252). What profile selection reads for `include-all`,
# `matching` and `with-child-controls`.
#
# `catalog_controls` also holds the statement-item rows an import derives
# (`ac-1a`, `ac-1a.1`); those are parts of a statement, not controls, and are
# left out. Controls and parents are told apart by the same rule the catalog
# export nests enhancements by (OscalCatalogExportService#top_level_control?).
#
# NIST 800-53: CM-2.
class CatalogControlTree
  CONTROL_ID = /\A[a-z]+-\d+(\.\d+)?\z/i
  PARENT_ID  = /\A([a-z]+-\d+)\.\d+\z/i

  def self.for(catalog)
    new(catalog).pairs
  end

  def initialize(catalog)
    @catalog = catalog
  end

  # @return [Array<Array(String, String|nil)>] [id, parent_id] in catalog order
  def pairs
    rows = CatalogControl.joins(:control_family)
                         .where(control_families: { control_catalog_id: @catalog.id })
                         .order("control_families.sort_order", "control_families.id",
                                Arel.sql("COALESCE(catalog_controls.sort_id, catalog_controls.control_id)"),
                                "catalog_controls.id")
                         .pluck(:control_id)
                         .select { |id| id.match?(CONTROL_ID) }
    known = rows.to_set
    rows.map do |id|
      parent = id[PARENT_ID, 1]
      [ id, (parent if known.include?(parent)) ]
    end
  end
end
