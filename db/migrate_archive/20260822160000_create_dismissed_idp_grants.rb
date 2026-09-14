# frozen_string_literal: true

# #860 — an administrator's decision that a grant is NOT going to be honoured.
#
# The unmatched-grant queue is otherwise stateless on purpose: an unresolvable
# grant is a current disagreement between the directory and the estate, and it
# heals by itself when someone creates the missing record. But a grant that is
# simply WRONG — a group misnamed in the IdP, a boundary that will never exist —
# never heals, and it recurs on every sign-in of every affected user. Left alone
# it accumulates until the queue is all noise and the real problems are invisible.
#
# So dismissal, unlike the queue it filters, is a deliberate decision with a
# lifecycle, and it gets a table. It is deliberately NOT an audit event: audit is
# an immutable record of what happened, not a place to keep current state that
# someone may later reverse.
#
# Dismissing changes nothing about access. The grant was already refused; this
# only stops SPARC asking about it again.
class CreateDismissedIdpGrants < ActiveRecord::Migration[8.1]
  def change
    return if table_exists?(:dismissed_idp_grants)

    create_table :dismissed_idp_grants do |t|
      # The canonical grant string, so a dismissal survives an administrator
      # having typed it in a different case than the IdP emits it.
      t.string :grant, null: false
      t.references :dismissed_by, null: true, foreign_key: { to_table: :users }
      t.string :reason
      t.timestamps
    end

    add_index :dismissed_idp_grants, :grant, unique: true
  end
end
