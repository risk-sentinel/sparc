# frozen_string_literal: true

# #1100 — existing SSPs carry ONE implementation statement per control, because
# the statement tree they should have come from was never stored. Measured on
# the demo estate: 149 statements for 150 controls, zero with more than one, for
# controls NIST divides into as many as nine addressable parts.
#
# The generator and the resolver are fixed for documents created from now on.
# This gives the same structure to documents that already exist, which otherwise
# would only get it by being regenerated — and regenerating an SSP throws away
# the author's work, which is the opposite of the point.
#
# ── Additive, never destructive ────────────────────────────────────────────
#
# `CatalogPartExtractorService#backfill_ssp_statements!` adds the MISSING
# statements and leaves existing rows untouched. That matters more than it
# looks: the `<control-id>_smt` row an SSP already has may carry
# `implementation_prose` somebody wrote, and replacing it to tidy the shape
# would destroy exactly the content this feature exists to hold.
#
# ── Ordering ───────────────────────────────────────────────────────────────
#
# Runs AFTER 20260905090000_backfill_catalog_control_parts, which populates the
# catalog side. Without parts in the catalog there is nothing to copy, and this
# would flag every document as needing re-association rather than doing work.
#
# ── Idempotency and resume-from-partial ────────────────────────────────────
#
#   * Each control's existing statement_ids are read before inserting, so a
#     re-run adds nothing it added before and a partial run resumes cleanly.
#   * Statement UUIDs are DERIVED (#397), so a re-run cannot change the identity
#     of a statement an exported document already references.
#   * A document whose catalog cannot be resolved is FLAGGED
#     (`statements_backfill_status = needs_reassociation`) rather than silently
#     skipped — the SSP show screen already reads that flag.
class BackfillSspStatementSubParts < ActiveRecord::Migration[8.1]
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

      # CDEFs share the same shape and the same extractor.
      CdefDocument.find_each do |cdef|
        count = CatalogPartExtractorService.new(cdef).backfill_cdef_statements!
        added += count.to_i
        say "cdef ##{cdef.id}: +#{count} statement(s)" if count.to_i.positive?
      rescue StandardError => e
        say "cdef ##{cdef.id}: statement backfill failed — #{e.class}: #{e.message}"
      end

      say "backfilled #{added} statement(s) in total"
    end
  end

  # Deliberately empty. The added rows are the structure these documents should
  # always have had; there is no prior state worth restoring, and deleting them
  # would take any prose authored against them since.
  def down; end
end
