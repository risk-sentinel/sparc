# frozen_string_literal: true

# #1114 — give existing assessment plans and results the objectives the resolver
# used to drop.
#
# `f3a6bdc7` fixed `OscalResolvedProfileCatalogService` to carry
# `assessment-objective` and `assessment-method` parts. Documents already in the
# database do not benefit on their own, for the reason #1100 taught the hard way:
# `resolved_catalog_json` is a CACHE, written when a profile is published and
# never revisited. Every profile resolved before this fix still holds a catalog
# with no objectives in it, so:
#
#   * `ControlObjectiveExtractorService#backfill!` reads that cache and finds
#     nothing, exactly as it did before the fix;
#   * a SAP or SAR generated from it keeps ONE flattened `objective` string per
#     control, which is what the owner reported.
#
# So this runs in two passes, and the ORDER is the whole point:
#
#   1. Re-resolve every profile that has a stored catalog, through the fixed
#      service. Same code path `ProfileDocumentsController` uses on publish.
#   2. Backfill objectives for every SAP and SAR, now that there is something to
#      read.
#
# Doing only the second — the obvious shape, and the one #1100's first attempt
# took — reads the stale cache and reports success having added nothing.
#
# ── Additive, never destructive ────────────────────────────────────────────
#
# `backfill!` skips any control that already HAS objectives, so an assessment an
# assessor has begun is untouched: their `status`, `assessor_name` and
# `assessor_notes` are on those rows. A document whose catalog cannot be resolved
# is FLAGGED (`objective_backfill_status = needs_reassociation`) rather than
# silently skipped — both screens already read that flag.
#
# Re-resolving a profile rewrites only `resolved_catalog_json`, which is derived
# data. It does not touch profile controls, parameters, or anything authored.
class BackfillAssessmentObjectives < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  def up
    defer_data_migration do
      resolved = 0
      ProfileDocument.where.not(resolved_catalog_json: nil).find_each do |profile|
        json = OscalResolvedProfileCatalogService.new(profile).export
        profile.update_columns(resolved_catalog_json: JSON.parse(json))
        resolved += 1
      rescue StandardError => e
        # One profile must not strand the rest; its documents simply keep the
        # cache they had and are reported below as adding nothing.
        say "profile ##{profile.id}: re-resolve failed — #{e.class}: #{e.message}"
      end
      say "re-resolved #{resolved} profile catalog(s) through the fixed resolver"

      added = 0
      [ SapDocument, SarDocument ].each do |klass|
        klass.find_each do |document|
          count = ControlObjectiveExtractorService.new(document).backfill!
          added += count.to_i
          say "#{klass.name.underscore} ##{document.id}: +#{count} objective(s)" if count.to_i.positive?
        rescue StandardError => e
          say "#{klass.name.underscore} ##{document.id}: objective backfill failed — #{e.class}: #{e.message}"
        end
      end

      say "backfilled #{added} assessment objective(s) in total"
    end
  end

  # Deliberately empty. The added rows are the structure these documents should
  # always have had, and deleting them would take any assessment recorded against
  # them since.
  def down; end
end
