# #934 — resolve the historical `collected_by` name on existing evidence to the
# account it names, where that resolution is unambiguous.
#
# Deferred (see app/lib/deferred_data_migration.rb): the schema_migrations row is
# recorded at db:migrate time and the body runs post-boot, so an instance with a
# large evidence corpus still comes up immediately.
#
# ── Why the match is built in Ruby ─────────────────────────────────────────
#
# The string was written as `display_name || email` (both create paths before
# this release) and is now written as `User#display_label`, which falls back
# through `display_name`, then `"first last"`, then `email`. That is a Ruby
# fallback chain, not a column, so the candidate identities are assembled here
# rather than expressed as a join. The accounts table is small; the evidence
# table is the large one, and it is touched with a single UPDATE per distinct
# name rather than a row-by-row save.
#
# ── Idempotency and resume-from-partial ────────────────────────────────────
#
#   * Every UPDATE is predicated on `collected_by_user_id IS NULL`, so a row
#     already attributed is never revisited. A re-run after a partial failure
#     converges instead of redoing work, and a later manual correction is not
#     stamped back over by a subsequent run.
#   * The work is derived entirely from current state — no cursor, no ordering
#     assumption — so an interrupted run resumes correctly from wherever it
#     stopped.
#
# ── What it deliberately does NOT do ───────────────────────────────────────
#
# It never writes `collected_by`. That string records what was true at collection
# time; rewriting it from the FK — even to "correct" a since-renamed account —
# would destroy the property that makes it audit evidence. The FK is an
# additional fact about the row, not a replacement for the one already there.
#
# It never guesses. A name matching two accounts (two people sharing a display
# name, or a display name that is also someone else's email) is left null and
# counted as ambiguous. A wrong attribution in an evidence package is worse than
# a missing one: a missing one is visibly missing, a wrong one is not.
#
# Rows created by `AuthoritativeSourceFetchService` before this release carry no
# `collected_by` at all — the bug #934 exists for — so there is nothing to match
# and they stay null. They are counted separately so an operator can see how many
# artifacts arrived unattributed rather than discovering it from a filter.
class BackfillEvidenceCollectedByUser < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  def up
    defer_data_migration do
      backfill_collected_by_user
    end
  end

  # Deliberately empty. The column is dropped by the schema migration's rollback;
  # clearing the FK on its own would discard correct attributions while leaving
  # the column in place, which is strictly worse than either state.
  def down
    # intentionally empty
  end

  def backfill_collected_by_user
    identities = user_identities

    matched   = 0
    ambiguous = 0
    unmatched = 0

    distinct_unattributed_names.each do |name|
      candidates = identities[normalize(name)]

      if candidates.nil? || candidates.empty?
        unmatched += 1
        next
      end

      if candidates.size > 1
        ambiguous += 1
        next
      end

      # `update_all`, deliberately: no callbacks, no validations. An evidence row
      # that is invalid for an unrelated reason must still get its provenance
      # recorded — the coupling that made #857/#892 a lockout.
      matched += Evidence.where(collected_by_user_id: nil, collected_by: name)
                         .update_all(collected_by_user_id: candidates.first)
    end

    blank = Evidence.where(collected_by_user_id: nil)
                    .where(collected_by: [ nil, "" ])
                    .count

    say "evidence provenance: #{matched} row(s) linked to an account; " \
        "#{unmatched} name(s) matched no account, #{ambiguous} matched more than one " \
        "(both left unattributed); #{blank} row(s) carry no collector name at all"

    # Returned so the runner records it as `records_processed` — an operator
    # checking whether the upgrade did its data work needs a number, not a status.
    matched
  end

  private

  # The distinct names still needing resolution. Reading distinct values rather
  # than rows keeps this proportional to the number of collectors, not to the
  # size of the evidence corpus.
  def distinct_unattributed_names
    Evidence.where(collected_by_user_id: nil)
            .where.not(collected_by: [ nil, "" ])
            .distinct
            .pluck(:collected_by)
  end

  # normalized identity => Set of user ids that answer to it.
  #
  # A user contributes every spelling that could have been written into
  # `collected_by`: their email, their display name, and their first+last name.
  # An identity claimed by two accounts lands in the same set and is therefore
  # rejected as ambiguous downstream — including the cross-field case where one
  # account's display name is another's email address.
  def user_identities
    identities = Hash.new { |hash, key| hash[key] = Set.new }

    User.find_each(batch_size: 500) do |user|
      full_name = [ user.first_name, user.last_name ].compact_blank.join(" ")

      [ user.email, user.display_name, full_name ].each do |candidate|
        key = normalize(candidate)
        identities[key] << user.id if key.present?
      end
    end

    identities
  end

  # Case- and whitespace-insensitive: "Ada Lovelace" and "ada lovelace " are the
  # same person, and email is case-insensitive by convention. Anything looser
  # than this starts guessing.
  def normalize(value)
    value.to_s.strip.downcase
  end
end
