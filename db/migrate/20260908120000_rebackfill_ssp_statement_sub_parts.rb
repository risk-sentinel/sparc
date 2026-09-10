# frozen_string_literal: true

# #1100 — 20260905140000_backfill_ssp_statement_sub_parts ran to COMPLETION
# against a broken extractor, and a completed run is never revisited.
#
# ── What happened ──────────────────────────────────────────────────────────
#
#   data_migration_runs
#     BackfillSspStatementSubParts   v1.0.0   completed   2026-09-05 15:25:37
#   4bc6e839 fixed CatalogPartExtractorService                2026-09-07 09:42
#
# The extractor read `ProfileDocument#resolved_catalog_json`, which is CACHED
# and predated the parts work, so it saw one part per control and added almost
# nothing. `4bc6e839` fixed it to read the stored `catalog_control_parts`, but by
# then the run row said `completed`:
#
#   * `DeferredDataMigrationRunner#run_all_pending` only selects rows in
#     `pending` or `failed` — a `completed` row is never picked up again.
#   * `register_pending_run!` is `find_or_create_by!(name:)`, so it will not
#     update an existing row's version either. Bumping `data_migration_version`
#     on the original class is therefore INERT; the version comparison the
#     comment in `deferred_data_migration.rb` describes is not implemented in
#     the runner.
#
# So every SSP that existed before 2026-09-07 still carries ONE statement per
# control, and nothing in the system would ever give it the sub-parts. Measured
# on the demo estate before this migration:
#
#   acme-hr-portal      150 controls   724 statements   (hand-run during 4bc6e839)
#   acme-cloud-platform 288 controls   287 statements   287 with exactly one
#
# ── Why a new class rather than a version bump ─────────────────────────────
#
# A new class name registers a NEW DataMigrationRun row, which the existing
# runner picks up with no change to shared infrastructure. Teaching the runner to
# honour a version bump is the general fix and is deliberately NOT done here.
#
# ── Safety ─────────────────────────────────────────────────────────────────
#
# `backfill_ssp_statements!` is additive: it reads each control's existing
# statement_ids first and inserts only what is missing, so an author's
# `implementation_prose` on the `<control-id>_smt` row is never replaced. That is
# exactly why this is safe to re-run over documents the hand-run already fixed —
# they simply add nothing.
class RebackfillSspStatementSubParts < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  def up
    defer_data_migration do
      added = 0

      SspDocument.find_each do |ssp|
        count = CatalogPartExtractorService.new(ssp).backfill_ssp_statements!
        added += count.to_i
        say "ssp ##{ssp.id}: +#{count} statement(s)" if count.to_i.positive?
      rescue StandardError => e
        # One document must not strand the rest.
        say "ssp ##{ssp.id}: statement backfill failed — #{e.class}: #{e.message}"
      end

      CdefDocument.find_each do |cdef|
        count = CatalogPartExtractorService.new(cdef).backfill_cdef_statements!
        added += count.to_i
        say "cdef ##{cdef.id}: +#{count} statement(s)" if count.to_i.positive?
      rescue StandardError => e
        say "cdef ##{cdef.id}: statement backfill failed — #{e.class}: #{e.message}"
      end

      say "re-backfilled #{added} statement(s) in total"
    end
  end

  # Deliberately empty, for the same reason as the original: the added rows are
  # the structure these documents should always have had, and deleting them would
  # take any prose authored against them since.
  def down; end
end
