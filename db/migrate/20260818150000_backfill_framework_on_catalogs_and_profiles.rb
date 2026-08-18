# #935 — backfill `framework` on rows that predate the column, through the SAME
# rule the importers use, so an existing instance filters as well as a fresh one.
#
# Deferred (see app/lib/deferred_data_migration.rb): the schema_migrations row is
# recorded at db:migrate time and the body runs post-boot, so an instance with a
# large catalog corpus still comes up immediately.
#
# ── Same rule, not a second one ────────────────────────────────────────────
#
# It calls FrameworkDeriver, not a copy of its regexes. A backfill that
# reimplements the rule is a rule that can drift from the one used at import,
# and then two rows with identical content disagree depending on when they
# arrived.
#
# ── What it will not do ────────────────────────────────────────────────────
#
#   * It never overwrites a value that is already set. A derivation must not
#     stamp over an operator's correction.
#   * It leaves a row null when no signal says clearly. "Unspecified" is honest;
#     a guess in a compliance tool is not, which is why #908 cut this rather
#     than shipping a title regex.
#
# ── Idempotency ────────────────────────────────────────────────────────────
#
# Every write is predicated on `framework IS NULL`, so a re-run after a partial
# failure converges rather than redoing work, and a later manual correction is
# not stamped back over.
class BackfillFrameworkOnCatalogsAndProfiles < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  def up
    defer_data_migration do
      derived = backfill(ControlCatalog.where(framework: nil)) { |c| FrameworkDeriver.for_catalog(c) }
      derived += backfill(ProfileDocument.where(framework: nil)) { |p| FrameworkDeriver.for_profile(p) }

      Rails.logger.info({ framework_backfill: { derived: derived } }.to_json)
    end
  end

  def down
    # Reversing would delete operator-set values along with derived ones.
  end

  private

  def backfill(scope)
    count = 0
    scope.find_each do |record|
      framework = yield(record)
      next if framework.blank?

      record.update_column(:framework, framework)
      count += 1
    end
    count
  end
end
