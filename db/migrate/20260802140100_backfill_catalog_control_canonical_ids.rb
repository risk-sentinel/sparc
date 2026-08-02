# #881 — populate catalog_controls.canonical_id for existing rows.
#
# Deferred (see app/lib/deferred_data_migration.rb): the schema_migrations row
# is recorded at db:migrate time while the body runs post-boot via
# DeferredDataMigrationJob, so the container comes up immediately.
#
# Idempotency and resume-from-partial:
#
#   * Only rows whose canonical_id is NULL or already stale are touched, so a
#     re-run after a partial failure resumes rather than redoing work.
#   * update_column, deliberately: this must not fire validations or callbacks.
#     A control that is invalid for some unrelated reason must still get its
#     identifier — the same coupling that made #857/#892 a lockout.
#   * A collision within a family is logged and SKIPPED rather than raised. The
#     unique index would abort the whole run over one bad row, stranding every
#     later control without an identifier. The fallback in
#     CatalogControl#canonical_identifier keeps those URLs working, and the
#     count is reported so a real collision is visible rather than silent.
#     (Measured: 0 collisions across all 4054 seeded controls.)
class BackfillCatalogControlCanonicalIds < ActiveRecord::Migration[8.1]
  include DeferredDataMigration

  def up
    defer_data_migration do
      backfill_canonical_ids
    end
  end

  def backfill_canonical_ids
    updated = 0
    skipped = 0

    CatalogControl.unscoped.find_each(batch_size: 500) do |control|
      canonical = ControlId.canonical(control.control_id)
      next if canonical.blank?
      next if control.canonical_id == canonical # already done — resume-safe

      if collides?(control, canonical)
        skipped += 1
        say "canonical_id collision in family #{control.control_family_id}: " \
            "#{control.control_id.inspect} -> #{canonical.inspect} (skipped)"
        next
      end

      control.update_column(:canonical_id, canonical)
      updated += 1
    end

    say "backfilled canonical_id on #{updated} catalog control(s); #{skipped} skipped"
  end

  # down is a no-op: the column is dropped by the schema migration's rollback,
  # and clearing the values on their own would only break URL resolution.
  def down
    # intentionally empty
  end

  private

  def collides?(control, canonical)
    CatalogControl.unscoped
                  .where(control_family_id: control.control_family_id, canonical_id: canonical)
                  .where.not(id: control.id)
                  .exists?
  end
end
