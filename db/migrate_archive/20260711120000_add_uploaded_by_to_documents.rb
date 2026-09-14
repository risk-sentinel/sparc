# frozen_string_literal: true

# #623 — persist the uploading user on every document type that goes through
# DocumentConversionJob. The stuck-document reaper runs async with no request
# context, so the uploader must live on the record for a failure notification to
# reach them. Nullable + on_delete: :nullify (a user deletion must not block the
# document); indexed for the notification lookup.
#
# Naming matches the existing review-workflow columns (submitted_by_user_id,
# approved_by_user_id). NIST 800-53: AC-3 / AU-2 (accountability — who introduced
# this artifact), SI-11 (error-handling notification).
class AddUploadedByToDocuments < ActiveRecord::Migration[8.1]
  TABLES = %w[
    ssp_documents sar_documents cdef_documents
    profile_documents sap_documents poam_documents
  ].freeze

  def change
    TABLES.each do |table|
      add_column table, :uploaded_by_user_id, :bigint
      add_index  table, :uploaded_by_user_id
      add_foreign_key table, :users, column: :uploaded_by_user_id, on_delete: :nullify
    end
  end
end
