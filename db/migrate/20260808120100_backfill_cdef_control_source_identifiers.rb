# #912 — move each existing CDEF control's identifier into `source_control_id`,
# label its vocabulary, and leave `control_id` holding only a NIST reference.
#
# Deferred (see app/lib/deferred_data_migration.rb): the schema_migrations row is
# recorded at db:migrate time while the body runs post-boot, so a container with
# a large CDEF corpus still comes up immediately.
#
# ── Idempotency and resume-from-partial ────────────────────────────────────
#
#   * A row whose `source_control_id` is already set is SKIPPED, so a re-run
#     after a partial failure resumes rather than redoing — and, critically,
#     never re-reads an already-migrated `control_id` as though it were the
#     source. Running this twice must not turn a resolved NIST id into the
#     "source" identifier.
#   * `update_columns`, deliberately: this must not fire validations or
#     callbacks. A control that is invalid for an unrelated reason must still
#     get its provenance recorded — the coupling that made #857/#892 a lockout.
#   * Rows are read `unscoped` so soft-deleted documents' controls migrate too;
#     leaving them behind would strand them in the old shape forever.
#
# ── What it does NOT do ─────────────────────────────────────────────────────
#
# ── An ordering hazard, deliberately accepted ───────────────────────────────
#
# #912 re-enables canonicalisation on `CdefControl#control_id` in the same
# deploy. Existing rows are untouched by that (it fires on write), so they still
# hold their original casing when this runs. But a row RE-SAVED through the model
# between the schema migration and this backfill completing has its `control_id`
# canonicalised first — `IAM.3` becomes `iam.3` — and the original casing is
# then unrecoverable from that column.
#
# Accepted because the window is the gap before the post-boot job runs, and the
# only writers in it are an import or a UI edit. An AWS row that does lose its
# casing is repaired on the next `AwsLabsCdefRefreshJob`, which re-derives
# `source_control_id` from the upstream fixture via `record_aws_source!`.
#
# It does not invent NIST references. Where the existing `control_id` is not
# already NIST (an AWS Security Hub id, an InSpec control name), `control_id` is
# CLEARED and the row is reported as unmapped — the same posture #911 established
# for STIG rules that resolve to nothing. Guessing a NIST control from a Security
# Hub id is exactly the unverifiable inference this issue exists to remove; the
# `aws_security_hub_to_nist` converter does that resolution at import, and a
# re-import or converter refresh fills it in.
class BackfillCdefControlSourceIdentifiers < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  def up
    defer_data_migration do
      backfill_source_identifiers
    end
  end

  # down is a no-op: the columns are dropped by the schema migration's rollback.
  # Clearing the values on their own would discard provenance while leaving
  # `control_id` already cleared, which is strictly worse than either state.
  def down
    # intentionally empty
  end

  def backfill_source_identifiers
    migrated = 0
    cleared  = 0

    CdefDocument.unscoped.find_each(batch_size: 100) do |document|
      vocabulary = vocabulary_for(document)

      document.cdef_controls.find_each(batch_size: 500) do |control|
        next if control.source_control_id.present? # resume-safe

        source = control.stig_id.presence || control.rule_id.presence || control.control_id.presence
        next if source.blank?

        updates = { source_control_id: source, source_vocabulary: vocabulary }

        # Only a NIST-vocabulary document's control_id is already a NIST
        # reference. Anything else was a source identifier wearing the NIST
        # column, so it is cleared rather than left to masquerade.
        if vocabulary != "nist" && control.control_id.present? && control.control_id == source
          updates[:control_id] = nil
          cleared += 1
        end

        control.update_columns(updates)
        migrated += 1
      end
    end

    say "backfilled source identifiers on #{migrated} CDEF control(s); " \
        "cleared #{cleared} non-NIST control_id value(s) into source_control_id"
  end

  private

  # Inferred from the document, not from the shape of the identifier. Sniffing
  # `IAM.3` versus `ac-2` is the guesswork this column exists to end.
  def vocabulary_for(document)
    return "aws_security_hub" if document.import_metadata.is_a?(Hash) &&
                                 document.import_metadata["source_type"] == "aws_labs"

    case document.cdef_type
    when "disa_stig" then "disa_stig"
    when "cis"       then "cis"
    when "scap"      then "scap_oval"
    else                  "nist"
    end
  end
end
