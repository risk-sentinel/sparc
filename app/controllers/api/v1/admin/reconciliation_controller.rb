# frozen_string_literal: true

# Instance-wide catalog-lineage report (#911, layer 2 of 3).
#
# The per-document `reconciliation` object answers "what is wrong with THIS
# document". This answers "how much of this instance is affected", which is the
# question an operator has before an upgrade lands on their users.
#
# Admin-only: it enumerates every document in the instance regardless of
# boundary membership, which is a deliberately wider view than any single
# author is entitled to.
class Api::V1::Admin::ReconciliationController < Api::V1::BaseController
  before_action :require_admin!

  # GET /api/v1/admin/reconciliation
  def index
    report = ReconciliationReportService.new

    render json: {
      data: {
        total: report.total,
        blocking: report.blocking_count,
        advisory: report.advisory_count,
        by_type: report.summary,
        documents: report.rows.map { |row| serialize_row(row) }
      }
    }
  end

  private

  def serialize_row(row)
    {
      type: row.type_label,
      id: row.document.id,
      slug: row.document.slug,
      name: row.document.name,
      # The same object the document itself reports and the same object a 422
      # refusal carries — one shape, three surfaces.
      reconciliation: row.reconciliation
    }
  end

  def require_admin!
    raise NotAuthorizedError, "Admin only" unless current_user&.admin?
  end
end
