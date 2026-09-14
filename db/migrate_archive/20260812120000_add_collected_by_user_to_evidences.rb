# #934 — give evidence provenance a reference to the account, not just a name.
#
# `evidences.collected_by` is a free-text copy of a display name captured at
# upload. Users are deactivated rather than deleted, so that string stays
# true-as-of-collection and satisfies audit — it is kept, and this column does
# not replace it.
#
# What the string cannot do is answer "show me every artifact this account
# provided", which is the question an assessor asks: two people sharing a
# display name are indistinguishable, and a rename leaves earlier rows
# correct-as-of-then but unlinkable to the account now. That is why the "added
# by" facet had to be cut from #908.
#
# Nullable by construction: a system-initiated fetch has no interactive user,
# and the backfill deliberately leaves ambiguous rows unattributed rather than
# guessing. `on_delete: :nullify` mirrors `uploaded_by_user_id` on the document
# tables — losing the FK must never take the evidence row with it, because the
# historical `collected_by` string on that row is still audit evidence.
class AddCollectedByUserToEvidences < ActiveRecord::Migration[8.1]
  def change
    return if column_exists?(:evidences, :collected_by_user_id)

    add_reference :evidences, :collected_by_user, null: true, index: true,
                  foreign_key: { to_table: :users, on_delete: :nullify }
  end
end
