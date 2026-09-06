# frozen_string_literal: true

# #1100 — `catalog_control_parts` is EMPTY on every existing instance: 0 rows
# against 4,054 catalog_controls on the demo estate, with no failure recorded
# anywhere.
#
# ── Why the table is empty ─────────────────────────────────────────────────
#
# Two independent defects, either of which alone produces the same symptom:
#
#   1. `CatalogImportService` flattened `ctrl["parts"]` into five named prose
#      fields on `guidance_data` and dropped the tree.
#      `CatalogPartExtractorService.backfill_catalog_parts!` then read
#      `guidance_data["parts"]` — a key nothing has ever written — so it skipped
#      every control, returned 0, and raised nothing.
#   2. `walk_parts` filtered on part names that omitted "item". NIST names a
#      control's statement part "statement" and every sub-part inside it "item",
#      so walking only "statement" captures the container and none of the
#      requirements. Measured on the shipped Rev 5 catalog: ac-1 yields 1 part
#      where it should yield 10.
#
# Both are fixed in the importer and the extractor. This resolves the rows
# already stored, which a re-import would otherwise be the only way to fix.
#
# ── The bound on what this can repair, stated plainly ──────────────────────
#
# SPARC stores `catalog_content_digest` and NEVER the source OSCAL — no column,
# no attachment. So parts can only be rebuilt for a catalog whose source bytes
# are still on disk under lib/data/catalogs, matched BY DIGEST rather than by
# filename: the digest proves the file is the content that was imported, a name
# does not.
#
# On the demo estate that covers the two NIST catalogs and not the FedRAMP 20x
# one, which carries no digest at all. On a customer instance it will cover
# whatever shipped with SPARC and nothing they imported themselves.
#
# A catalog this cannot repair is FLAGGED on `metadata_extra` rather than left
# silently empty — the original backfill's failure was precisely that "no parts
# found" and "no parts stored" looked identical from the outside. That is the
# same trace #968 added for the best-effort import path.
#
# ── Idempotency and resume-from-partial ────────────────────────────────────
#
#   * The write is an upsert keyed on the table's own unique index
#     (catalog_control_id, part_id), so a re-run converges instead of
#     duplicating, and a partially-populated catalog is completed rather than
#     redone.
#   * Part UUIDs are DERIVED (OscalUuidService), so a re-run cannot change the
#     identity of a part an exported document already references (#397).
#   * Catalogs that already hold parts are skipped, including any an operator
#     populated by hand.
class BackfillCatalogControlParts < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  def up
    defer_data_migration do
      sources = shipped_sources

      ControlCatalog.find_each do |catalog|
        next if parts_count(catalog).positive?

        json = sources[catalog.catalog_content_digest]
        if json.blank?
          flag_unrepairable(catalog)
          next
        end

        CatalogImportService.new(StringIO.new(json), "backfill.json", existing_catalog: catalog).call
        say "catalog ##{catalog.id}: #{parts_count(catalog)} part(s) rebuilt"
      rescue StandardError => e
        # One bad catalog must not strand the rest.
        say "catalog ##{catalog.id}: parts rebuild failed — #{e.class}: #{e.message}"
        flag_unrepairable(catalog, error: "#{e.class}: #{e.message}".truncate(300))
      end
    end
  end

  # Deliberately empty. These rows were absent because of the defect, not by
  # anyone's choice, so there is no prior state to restore.
  def down; end

  private

  def parts_count(catalog)
    CatalogControlPart.joins(catalog_control: :control_family)
                      .where(control_families: { control_catalog_id: catalog.id })
                      .count
  end

  def shipped_sources
    Dir[Rails.root.join("lib/data/catalogs/*.json")].to_h do |path|
      body = File.read(path)
      [ Digest::SHA256.hexdigest(body), body ]
    end
  end

  def flag_unrepairable(catalog, error: nil)
    say "catalog ##{catalog.id} (#{catalog.name}): no matching source on disk — " \
        "re-import it to populate control parts"
    catalog.update_column(
      :metadata_extra,
      (catalog.metadata_extra || {}).merge(
        { "catalog_parts_backfill_skipped_at" => Time.current.iso8601,
          "catalog_parts_backfill_reason"     => error || "source OSCAL not retained; re-import required" }
      )
    )
  end
end
