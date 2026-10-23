# frozen_string_literal: true

# CatalogHierarchyBackfill — records, on catalogs imported before #1252, which
# catalog_controls rows are OSCAL controls and which control each one sits
# under (`parent_control_id`), and which rows are statement items an import
# derived from a control's statement (`statement_item`).
#
# Imports write both columns from the tree they walk. Older rows carry neither,
# and the catalog file is not kept, so the tree is reconstructed:
#
#   1. statement items, EXACTLY: an import names an item row after its owning
#      control and the item's label (`ac-1` + "a." -> `ac-1a`, + "1." ->
#      `ac-1a.1`, + "(a)" -> `ac-1a.1.(a)`). Each control's stored statement
#      parts carry those labels, so the item rows are recomputed from them.
#   2. where a control has no stored parts (a catalog imported before #1100),
#      a row is an item when it extends another row's id by a letter, the way
#      NIST's item ids do (CatalogControl.statement_item_owner).
#   3. a control's parent is the nearest other control whose id it extends
#      (`ac-2.1` under `ac-2`; `ac-20` is not under `ac-2`). FedRAMP 20x
#      indicators (`ksi-auth-01`) extend nothing and stay top-level.
#
# Idempotent: it rewrites both columns from the same inputs every time.
# Returns counts per catalog for the migration to print.
#
# NIST 800-53: CM-2, SI-7.
class CatalogHierarchyBackfill
  STATEMENT_PARTS = %w[statement item].freeze

  def self.run(catalogs = ControlCatalog.all)
    catalogs.find_each.map { |catalog| new(catalog).run }
  end

  def initialize(catalog)
    @catalog = catalog
  end

  def run
    rows = CatalogControl.joins(:control_family)
                         .where(control_families: { control_catalog_id: @catalog.id })
                         .pluck(:id, :control_id)
    ids_by_control = rows.to_h { |id, cid| [ cid, id ] }

    items = items_from_parts(rows, ids_by_control)
    by_parts = items.size
    items.merge!(items_from_ids(ids_by_control.keys, items))

    controls = ids_by_control.keys - items.keys
    parents = controls.to_h { |cid| [ cid, nearest_ancestor(cid, controls) ] }

    write(ids_by_control, items, parents)
    { catalog_id: @catalog.id, controls: controls.size, items_from_parts: by_parts,
      items_from_ids: items.size - by_parts, with_parent: parents.values.compact.size }
  end

  private

  # item control_id => owning control_id, from each control's labelled statement parts.
  def items_from_parts(rows, ids_by_control)
    parts = CatalogControlPart.where(catalog_control_id: rows.map(&:first), part_name: STATEMENT_PARTS)
                              .pluck(:catalog_control_id, :part_id, :parent_part_id, :part_name, :label)
                              .group_by(&:first)
    owner_by_row = rows.to_h { |id, cid| [ id, cid ] }

    parts.each_with_object({}) do |(row_id, list), items|
      owner = owner_by_row[row_id]
      by_part = list.to_h { |_, part_id, parent_part_id, name, label| [ part_id, [ parent_part_id, name, label ] ] }
      derived = {}
      # Each item resolves through its own parent chain, so the order rows
      # come back in does not matter.
      list.each do |_, part_id, _, name, label|
        next unless name == "item" && label.present?

        id = derived_id(part_id, by_part, owner, derived)
        items[id] = owner if id && ids_by_control.key?(id) && id != owner
      end
    end
  end

  # The row id an import gave this part: its parent's id plus its label. nil
  # when the chain has an unlabelled item or a parent that is not stored.
  def derived_id(part_id, by_part, owner, derived)
    return derived[part_id] if derived.key?(part_id)

    parent_part_id, name, label = by_part[part_id]
    derived[part_id] =
      if name == "statement" then owner
      elsif name == "item" && label.present?
        base = parent_part_id.nil? ? owner : (by_part.key?(parent_part_id) && derived_id(parent_part_id, by_part, owner, derived))
        base && base + CatalogImportService.label_suffix(label)
      end
  end

  # Only for rows the parts did not classify, on controls with no stored parts.
  def items_from_ids(all_ids, known_items)
    unresolved = all_ids - known_items.keys
    unresolved.each_with_object({}) do |cid, items|
      owner = CatalogControl.statement_item_owner(cid, unresolved)
      items[cid] = owner if owner
    end
  end

  def nearest_ancestor(cid, controls)
    controls.select { |other| CatalogControl.descendant?(cid, other) }.max_by(&:length)
  end

  def write(ids_by_control, items, parents)
    CatalogControl.transaction do
      ids_by_control.each do |cid, row_id|
        if items.key?(cid)
          CatalogControl.where(id: row_id).update_all(statement_item: true, parent_control_id: items[cid])
        else
          CatalogControl.where(id: row_id).update_all(statement_item: false, parent_control_id: parents[cid])
        end
      end
    end
  end
end
