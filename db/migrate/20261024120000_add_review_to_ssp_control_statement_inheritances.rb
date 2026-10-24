# frozen_string_literal: true

# #1242 — who reviewed text a CDEF filled in, and when.
#
# A statement filled from a CDEF counts as implemented, but nobody has said the
# CDEF's text is true of THIS system. Editing it already marks the link
# overridden; these record a review that keeps the text as it is. A refresh that
# changes the text, or a reset to the source, clears them.
#
# Existing links need no backfill: none has been reviewed.
class AddReviewToSspControlStatementInheritances < ActiveRecord::Migration[8.1]
  def change
    add_column :ssp_control_statement_inheritances, :reviewed_at, :datetime
    add_reference :ssp_control_statement_inheritances, :reviewed_by_user,
                  foreign_key: { to_table: :users, on_delete: :nullify },
                  index: { name: "idx_inh_on_reviewed_by" }
  end
end
