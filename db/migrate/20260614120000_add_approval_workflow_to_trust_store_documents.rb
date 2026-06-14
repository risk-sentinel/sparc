# frozen_string_literal: true

# #630 — Review/approval workflow for trust-store documents (Catalog, Profile,
# Baseline, CDEF). Adds the approval state machine columns to the three backing
# tables (Profile + Baseline both live on profile_documents):
#
#   approval_status       draft → pending_review → approved / rejected
#   submitted_by/_at      who requested review + when
#   approved_by/_at       who approved + when
#   rejection_reason      why a review was rejected
#
# Mirrors the back-matter promotion columns (#372). Enforcement of the
# publish-requires-approval gate is config-flagged (SPARC_REQUIRE_DOCUMENT_APPROVAL),
# so this migration is additive and safe to deploy ahead of enabling the gate.
#
# Idempotent per docs/dev/issue_rules.md migration-safety rules: every column is
# guarded by column_exists?, the default backfills existing rows to "draft", and
# the FKs are nullable.
#
# NIST 800-53: CA-6 (Authorization), SA-10 (Developer Config Management),
# AU-2/AU-3 (audit of state transitions, via AuditEvent).
class AddApprovalWorkflowToTrustStoreDocuments < ActiveRecord::Migration[8.1]
  TABLES = %i[control_catalogs profile_documents cdef_documents].freeze

  def change
    TABLES.each do |table|
      unless column_exists?(table, :approval_status)
        add_column table, :approval_status, :string, default: "draft", null: false
      end
      add_column table, :submitted_by_user_id, :bigint unless column_exists?(table, :submitted_by_user_id)
      add_column table, :submitted_at, :datetime unless column_exists?(table, :submitted_at)
      add_column table, :approved_by_user_id, :bigint unless column_exists?(table, :approved_by_user_id)
      add_column table, :approved_at, :datetime unless column_exists?(table, :approved_at)
      add_column table, :rejection_reason, :text unless column_exists?(table, :rejection_reason)

      add_index table, :approval_status unless index_exists?(table, :approval_status)
      add_index table, :submitted_by_user_id unless index_exists?(table, :submitted_by_user_id)
      add_index table, :approved_by_user_id unless index_exists?(table, :approved_by_user_id)
    end
  end
end
