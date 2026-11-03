# frozen_string_literal: true

# #1328 — every existing SSP gets a statement row for each item its baseline
# requires, so Edit offers every item the control's badge counts.
#
# The third pass at this, and why it is different:
#
#   20260905140000 BackfillSspStatementSubParts   read a cached, flattened
#                                                 catalog and added almost nothing
#   20260908120000 RebackfillSspStatementSubParts fixed the reader, but ran once,
#                                                 over the SSPs that existed then,
#                                                 and read the parts only from a
#                                                 baseline's LINKED catalog
#
# An SSP created or imported after 2026-09-08, or whose baseline names no
# catalog, kept one `<control>_smt` row per control. v1.17.5's editor (#1312)
# answers only rows that exist, so those SSPs offered nothing but Notes while
# their badges counted "0/6 answered".
#
# SspStatementRows reads the items from ControlRequirementText, the source the
# badge counts from, so what is counted gets a row. SSP creation and import now
# call it too, so no SSP is left in the old shape again.
#
# A new class rather than a version bump: a completed DataMigrationRun is never
# revisited (see 20260908120000).
#
# Additive and idempotent: an existing row is never changed, a re-run adds
# nothing, and one document's failure does not strand the rest.
class EnsureSspStatementRows < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  def up
    defer_data_migration do
      added = 0
      SspDocument.find_each do |ssp|
        count = SspStatementRows.ensure!(ssp)
        added += count
        say "ssp ##{ssp.id}: +#{count} statement row(s)" if count.positive?
      rescue StandardError => e
        say "ssp ##{ssp.id}: statement rows failed — #{e.class}: #{e.message}"
      end
      say "added #{added} statement row(s) in total"
    end
  end

  def down
    # Deliberately empty: the rows are the structure these documents should have
    # had, and answers written into them since must not be deleted.
  end
end
