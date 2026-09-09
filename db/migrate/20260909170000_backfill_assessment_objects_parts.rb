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
# ── Additive and idempotent ────────────────────────────────────────────────
#
# Only rows whose `part_id` is absent are inserted, so a re-run adds nothing and
# nothing already stored is rewritten. The derived ids are deterministic
# (`<method-id>_objects`), so the same file always produces the same rows.
#
# A catalog with no matching file on disk is skipped and SAID so, rather than
# silently leaving the operator to wonder why one catalog gained parts and
# another did not.
class BackfillAssessmentObjectsParts < ActiveRecord::Migration[8.1]
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
          parts = CatalogPartExtractorService.parts_for_control(
            json, control.control_id,
            part_names: [ "assessment-objects" ]
          )
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
