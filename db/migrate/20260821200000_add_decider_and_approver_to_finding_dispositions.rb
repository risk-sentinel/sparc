# #1034 — separation of duties on finding dispositions needs an identity to
# compare, and the table records only names.
#
# `decided_by` and `approved_by` are strings — a display name falling back to an
# email. Guarding on those would be weak: two users can share a display name, and
# a user can change theirs between deciding and approving. `DocumentApprovalService`
# compares `submitted_by_user_id` for exactly this reason.
#
# The string columns stay. They are the human-readable provenance the export and
# the signature hash already use, and they remain correct for rows written before
# this migration — which is also why the new columns are nullable rather than
# backfilled by matching names. A guess at which user a name referred to is not
# provenance, and the guard is written to be inert where the id is NULL.
class AddDeciderAndApproverToFindingDispositions < ActiveRecord::Migration[8.1]
  def change
    add_reference :finding_dispositions, :decided_by_user,
                  null: true, foreign_key: { to_table: :users }, index: true
    add_reference :finding_dispositions, :approved_by_user,
                  null: true, foreign_key: { to_table: :users }, index: true
  end
end
