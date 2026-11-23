# frozen_string_literal: true

# #1390 part G — the received-document viewer.
#
#   received_documents.review_questions  the reviewer's questions to the
#                                        provider, each tied to a place in the
#                                        document (pointer, location, the values
#                                        compared, the question). Exported to
#                                        share out of band; #1394 automates
#                                        delivery later.
#   received_documents.compared_with_id  the version this one's recorded
#                                        comparison was made against (the
#                                        version in effect when it arrived), so
#                                        the viewer can show both side by side.
#                                        Null for a first version, an invalid
#                                        one, and versions stored before this.
#
# Idempotent (docs/dev/issue_rules.md, migration rules 1–6). Both columns are
# nullable or defaulted, so existing rows need no backfill.
class AddReviewQuestionsToReceivedDocuments < ActiveRecord::Migration[8.1]
  def up
    unless column_exists?(:received_documents, :review_questions)
      add_column :received_documents, :review_questions, :jsonb, null: false, default: []
    end

    unless column_exists?(:received_documents, :compared_with_id)
      add_reference :received_documents, :compared_with, null: true, index: true,
                                                        foreign_key: { to_table: :received_documents, on_delete: :nullify }
    end
  end

  def down
    if column_exists?(:received_documents, :compared_with_id)
      remove_reference :received_documents, :compared_with, index: true, foreign_key: { to_table: :received_documents }
    end
    remove_column :received_documents, :review_questions if column_exists?(:received_documents, :review_questions)
  end
end
