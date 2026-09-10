# frozen_string_literal: true

# #1114 — add the `assessment-objects` parts the importer used to discard.
#
# `9d603817` taught `CatalogPartExtractorService` to keep them. Catalogs already
# imported do not have them, and cannot recover them from anything in the
# database: `backfill_catalog_parts!` reconstructs from `guidance_data`, which is
# the FLATTENED blob the objects were never in. Measured on the seeded estate —
# 2,931 `assessment-method` rows, and ZERO children:
#
#   {"guidance"=>1766, "assessment-method"=>2931, "statement"=>1842,
#    "item"=>1882, "assessment-objective"=>3715}
#
# So a method says EXAMINE and the assessment plan cannot say what to examine,
# which is the gap the owner reported.
#
# The only honest source is the catalog JSON the catalog was imported FROM,
# which ships in the repo and is what `db/seeds.rb` loads. Anything derived from
# the database would be inventing evidence references, and this is exactly the
# kind of content that must not be invented.
#
# ── Why V2 ─────────────────────────────────────────────────────────────────
#
# The first version asked the extractor for `assessment-objects` ALONE.
# `walk_parts` advances `parent_part_id` only for parts in the allowlist, so the
# method was not in the chain, the child's parent came through nil, and
# `synthetic_part_id` — which refuses to derive an id with no parent — returned
# nothing. It completed having added 0 rows.
#
# A completed `DataMigrationRun` is never revisited (#1100), so the corrected
# body needs a new class name to register a new run. Proven against the shipped
# catalog before rebuilding: asking for `assessment-objects` alone captures 0 for
# ac-1; asking for the method and its objects captures 2.
#
# ── Additive and idempotent ────────────────────────────────────────────────
#
# Only rows whose `part_id` is absent are inserted, so a re-run adds nothing and
# nothing already stored is rewritten. The derived ids are deterministic
# (`<method-id>_objects`), so the same file always produces the same rows.
#
# A catalog with no matching file on disk is skipped and SAID so, rather than
# silently leaving the operator to wonder why one catalog gained parts and
# another did not.
class BackfillAssessmentObjectsPartsV2 < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  SOURCES = {
    /rev\s*5|revision\s*5/i => "lib/data/catalogs/NIST_SP-800-53_rev5_catalog.json",
    /rev\s*4|revision\s*4/i => "lib/data/catalogs/NIST_SP-800-53_rev4_catalog.json"
  }.freeze

  def up
    defer_data_migration do
      added = 0

      ControlCatalog.find_each do |catalog|
        path = source_path_for(catalog)
        if path.nil?
          say "catalog ##{catalog.id} (#{catalog.name.to_s.truncate(50)}): no source file — skipped"
          next
        end

        json = JSON.parse(File.read(path))
        catalog.catalog_controls.includes(:catalog_control_parts).find_each do |control|
          # The METHOD must be walked too, even though only its child is
          # inserted. `walk_parts` advances `parent_part_id` ONLY for parts in
          # the allowlist, so asking for `assessment-objects` alone leaves the
          # method out of the chain, the child's parent is nil, and
          # `synthetic_part_id` — which refuses to derive an id with no parent —
          # returns nothing. Measured: the first run of this migration completed
          # having added 0 rows, for exactly that reason.
          parts = CatalogPartExtractorService.parts_for_control(
            json, control.control_id,
            part_names: %w[assessment-method assessment-objects]
          ).select { |part| part[:part_name] == "assessment-objects" }
          next if parts.empty?

          existing = control.catalog_control_parts.pluck(:part_id).to_set
          parts.each do |part|
            next if existing.include?(part[:part_id])

            control.catalog_control_parts.create!(
              part_id:        part[:part_id],
              part_name:      part[:part_name],
              parent_part_id: part[:parent_part_id],
              label:          part[:label],
              prose:          part[:prose],
              props_data:     part[:props_data],
              row_order:      part[:row_order].to_i,
              uuid:           SecureRandom.uuid
            )
            added += 1
          end
        end
      rescue StandardError => e
        say "catalog ##{catalog.id}: assessment-objects backfill failed — #{e.class}: #{e.message}"
      end

      say "added #{added} assessment-objects part(s)"
    end
  end

  # Deliberately empty. These rows are content the catalog always had and the
  # importer dropped; there is no prior state worth restoring.
  def down; end

  private

  def source_path_for(catalog)
    SOURCES.each do |pattern, relative|
      next unless catalog.name.to_s.match?(pattern)

      path = Rails.root.join(relative)
      return path if File.exist?(path)
    end
    nil
  end
end
