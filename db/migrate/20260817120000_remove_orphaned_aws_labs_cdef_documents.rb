# #939 — remove the CdefDocument shells that failed AWS Labs imports left behind.
#
# Deferred (see app/lib/deferred_data_migration.rb): the schema_migrations row is
# recorded at db:migrate time and the body runs post-boot.
#
# ── What these rows are ────────────────────────────────────────────────────
#
# `write_through_parser` created the document BEFORE running the parser. The
# parser opens its own transaction and rolls back cleanly, but the `create!`
# above it did not, so a parse failure left a shell: status "processing", zero
# controls, zero components, and — because the AWS provenance was merged in
# only AFTER the parse succeeded — no `source_type`. That last part is what made
# them permanent: `CdefDocument.aws_labs_sourced` keys on
# `import_metadata->>'source_type'`, so the obvious cleanup
# (`aws_labs_sourced.destroy_all`) matched none of them, and the dedupe in
# `import_one` could not see them either, so each retry leaked another instead
# of reusing the last. 82 were measured on one instance after four passes.
#
# They were user-visible at the top of the CDEF index (it sorts newest-first)
# and they broke OSCAL export, because a component definition with no controls
# fails schema validation.
#
# The import is transactional as of this release, so no new ones can appear.
# This clears the ones already stored, which nothing else can reach.
#
# ── Why this is safe to run where the ingest never ran ─────────────────────
#
# `SPARC_AWS_LABS_CDEF_ENABLED` defaults to false, so most instances have no
# such rows and this is a no-op. It was written defensively because whether any
# deployed instance ever enabled the ingest was not known at the time.
#
# ── The identification is deliberately over-constrained ────────────────────
#
# These rows carry no marker saying "I am a failed AWS Labs import" — that is
# the defect. So they are identified by the conjunction of SEVEN conditions,
# every one of which must hold. A hand-authored document would have to match all
# seven to be at risk, and any one of them failing spares it:
#
#   1. status = "processing"      — a completed import is never touched
#   2. zero cdef_controls         — the row carries no content
#   3. zero cdef_components       — nor any indexed component
#   4. source_type IS NULL        — a correctly-tagged AWS row is never touched
#   5. cloned_from_id IS NULL     — a user's clone is never touched (#466 rule)
#   6. no attached file           — an interactive upload is never touched; that
#                                   path attaches the file before conversion, so
#                                   a genuinely stuck upload keeps its evidence
#                                   and stays visible as a failure to retry
#   7. name matches "AWS x (oscal y)" — the shape `derive_name` produces
#
# Condition 6 is what separates this from the interactive upload path, which has
# a superficially similar create-then-parse shape but is NOT the same defect: it
# attaches a file and moves to "failed", which is a legitimate, visible,
# retryable state. Deleting those would destroy a user's upload.
#
# Every name removed is logged, because a deletion that cannot be reviewed
# afterwards is not something to run unattended.
#
# ── Idempotency ────────────────────────────────────────────────────────────
#
# The work is derived entirely from current state and the predicate stops
# matching once a row is gone, so a re-run after a partial failure converges and
# a second run is a no-op. There is no cursor to resume.
class RemoveOrphanedAwsLabsCdefDocuments < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  def up
    defer_data_migration do
      remove_orphaned_shells
    end
  end

  # Deliberately empty — these rows are unreachable wreckage, and recreating
  # them would restore a broken CDEF index and a broken OSCAL export.
  def down
    # intentionally empty
  end

  def remove_orphaned_shells
    orphans = orphan_scope.pluck(:id, :name)

    if orphans.empty?
      say "AWS Labs orphan cleanup: no orphaned shells found"
      return 0
    end

    orphans.each do |id, name|
      say "AWS Labs orphan cleanup: removing CdefDocument #{id} #{name.inspect}"
    end

    # delete_all, deliberately: `CdefDocument` includes SafeDestroyable, whose
    # guards exist to protect documents other records depend on. These rows have
    # no controls, no components and nothing pointing at them, and a guard
    # refusing one would leave exactly the wreckage this is here to clear.
    removed = CdefDocument.unscoped.where(id: orphans.map(&:first)).delete_all

    say "AWS Labs orphan cleanup: removed #{removed} orphaned shell document(s)"
    removed
  end

  private

  def orphan_scope
    CdefDocument
      .unscoped
      .where(status: "processing")
      .where(cloned_from_id: nil)
      .where("import_metadata->>'source_type' IS NULL")
      .where("name LIKE ?", "AWS %(oscal %)")
      # `NOT IN (subquery)` evaluates to NULL — and therefore matches NOTHING —
      # if the subquery yields a single NULL. Excluding NULLs explicitly keeps
      # this a real filter rather than a silent no-op should either FK ever
      # become nullable.
      .where.not(id: CdefControl.unscoped.where.not(cdef_document_id: nil).select(:cdef_document_id))
      .where.not(id: CdefComponent.unscoped.where.not(cdef_document_id: nil).select(:cdef_document_id))
      .where.not(
        id: ActiveStorage::Attachment.where(record_type: "CdefDocument", name: "file").select(:record_id)
      )
  end
end
