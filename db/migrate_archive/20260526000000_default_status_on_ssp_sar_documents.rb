# frozen_string_literal: true

# Issue #557 — SSP and SAR `status` columns were left nullable with no
# default, so API-created documents returned `status: null` while every
# other document type returned a string (typically "pending"). This
# migration:
#
#   1. Backfills existing NULL rows to "pending"
#   2. Adds a `default: "pending"` to the column so new inserts always
#      have a non-null status
#
# Idempotent and safe to run repeatedly. CDEF and POAM already have this
# default; this brings SSP and SAR in line with the rest of the document
# family.
class DefaultStatusOnSspSarDocuments < ActiveRecord::Migration[8.1]
  def up
    %i[ssp_documents sar_documents].each do |table|
      next unless table_exists?(table) && column_exists?(table, :status)

      execute "UPDATE #{table} SET status = 'pending' WHERE status IS NULL"

      change_column_default table, :status, from: nil, to: "pending"
    end
  end

  def down
    %i[ssp_documents sar_documents].each do |table|
      next unless table_exists?(table) && column_exists?(table, :status)
      change_column_default table, :status, from: "pending", to: nil
    end
  end
end
