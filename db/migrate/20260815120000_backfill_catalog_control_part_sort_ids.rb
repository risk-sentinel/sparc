# #941 — give statement sub-parts the sort key their parent already has, so they
# order directly under it instead of after the last control in the family.
#
# Deferred (see app/lib/deferred_data_migration.rb): the schema_migrations row is
# recorded at db:migrate time and the body runs post-boot, so an instance with
# several loaded catalogs still comes up immediately.
#
# ── Why these rows are NULL in the first place ─────────────────────────────
#
# Not a failed import. OSCAL emits `props.sort-id` on controls — all 1196 of
# them in the Rev 5 catalog, and `CatalogImportService` reads every one — and on
# none of its 11159 `part` elements. The sub-part ROWS, however, are SPARC's
# own: `import_*_item_parts` mints "ac-2.7" + ".(a)" → "ac-2.7.(a)" itself and,
# until this release, called `upsert_catalog_control` without a `sort_id:`.
# So SPARC invented the identifier and declined to invent the sort key.
#
# The consequence is `default_scope { order(COALESCE(sort_id, control_id)) }`
# comparing an unpadded "ac-2.7.(a)" against a padded "ac-25": the two are in
# different vocabularies, and the sub-part sorts after AC-25.
#
# The importer now derives the key going forward. This resolves the rows already
# stored, which a re-import would otherwise be the only way to fix.
#
# ── How the parent is found ────────────────────────────────────────────────
#
# By longest proper prefix within the family, not by a stored FK — there is no
# parent_id column, and the identifier is the only expression of the hierarchy.
# "ac-2.7.(a)" resolves to "ac-2.7" rather than "ac-2" because the longest match
# wins. Rows are processed shortest-identifier-first so a parent is always
# resolved before its children, and a sub-part two levels down inherits through
# the key its own parent was just given.
#
# ── Idempotency and resume-from-partial ────────────────────────────────────
#
#   * Every write is predicated on `sort_id IS NULL`, so a row that already has
#     a key is never revisited — including one an operator set by hand. A re-run
#     after a partial failure converges rather than redoing work.
#   * The work is derived entirely from current state, with no cursor and no
#     ordering assumption beyond the within-run shortest-first pass, so an
#     interrupted run resumes correctly from wherever it stopped.
#
# ── What it deliberately does NOT do ───────────────────────────────────────
#
# It never overwrites a sort_id that is present. A key that came from the
# catalog is authoritative; a derived one is our reconstruction, and preferring
# ours over NIST's would be wrong in exactly the cases that matter.
#
# It leaves a row NULL when no ancestor in the family is a prefix of its
# identifier — NIST XML enhancement sub-parts keep their own parenthesised
# numbering, which is not built from the parent-id. The COALESCE fallback still
# orders those, imperfectly but no worse than before. Fabricating a key for an
# identifier we cannot place would put the row somewhere confidently wrong.
class BackfillCatalogControlPartSortIds < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  def up
    defer_data_migration do
      backfill_part_sort_ids
    end
  end

  # Deliberately empty. These rows held NULL because of the bug, not by
  # intention, and re-NULLing them would restore the broken ordering while
  # discarding keys a re-import may since have set correctly.
  def down
    # intentionally empty
  end

  def backfill_part_sort_ids
    derived   = 0
    unplaced  = 0

    family_ids_with_gaps.each do |family_id|
      # control_id => sort_id, for the whole family. Held in memory because a
      # sub-part's key depends on the key its parent was given earlier in this
      # same pass, which no single SQL statement expresses.
      keys = CatalogControl.unscoped
                           .where(control_family_id: family_id)
                           .pluck(:control_id, :sort_id)
                           .to_h

      pending = CatalogControl.unscoped
                              .where(control_family_id: family_id, sort_id: nil)
                              .pluck(:id, :control_id)
                              .sort_by { |_id, control_id| control_id.to_s.length }

      pending.each do |id, control_id|
        sort_id = derive(control_id, keys)

        if sort_id.blank?
          unplaced += 1
          next
        end

        # update_all, deliberately: no callbacks, no validations, and no
        # default_scope ordering on a write. A catalog control that is invalid
        # for an unrelated reason must still get its ordering fixed.
        derived += CatalogControl.unscoped
                                 .where(id: id, sort_id: nil)
                                 .update_all(sort_id: sort_id)
        keys[control_id] = sort_id
      end
    end

    say "catalog sub-part ordering: #{derived} row(s) given a sort key derived " \
        "from their parent; #{unplaced} row(s) had no ancestor whose identifier " \
        "is a prefix of theirs and were left to the COALESCE fallback"

    # Returned so the runner records it as `records_processed` — an operator
    # checking whether the upgrade did its data work needs a number, not a status.
    derived
  end

  private

  # Only families that actually have a gap, so a fully-keyed catalog costs one
  # query rather than a load of every control in it.
  def family_ids_with_gaps
    CatalogControl.unscoped.where(sort_id: nil).distinct.pluck(:control_family_id).compact
  end

  # The parent's key plus whatever this identifier adds to the parent's, which
  # keeps both in one padded vocabulary: "ac-02.07" + ".(a)" → "ac-02.07.(a)".
  #
  # Falls back to the parent's own identifier when the parent is itself unkeyed
  # and unresolvable — no worse than the COALESCE it replaces, and it keeps a
  # child ordered under its parent rather than under the family.
  def derive(control_id, keys)
    parent_id = longest_prefix(control_id, keys)
    return nil if parent_id.blank?

    base = keys[parent_id].presence || parent_id
    "#{base}#{control_id.delete_prefix(parent_id)}"
  end

  # The longest identifier in the family that is a proper prefix of this one.
  # Proper: a control is not its own parent.
  def longest_prefix(control_id, keys)
    keys.keys
        .select { |candidate| candidate.present? && candidate != control_id && control_id.start_with?(candidate) }
        .max_by(&:length)
  end
end
