# frozen_string_literal: true

# #809 — aggregate a boundary's scanner findings + dispositions into its SSP / SAP
# / SAR / POA&M documents.
#
#   POST /api/v1/authorization_boundaries/:authorization_boundary_id/aggregate
#     ?async=true  → enqueue AggregateFindingsJob, 202 Accepted
#     (default)    → run synchronously, 200 with the per-document summary
#
# NIST 800-53: IA-2 (token auth), AC-3/AC-6 (boundary-scoped RBAC), CA-7/CA-5/SI-2,
# AU-12 (audit).
class Api::V1::AggregationsController < Api::V1::BaseController
  before_action :set_boundary
  before_action :authorize_write!

  def create
    if params[:async] == "true"
      AggregateFindingsJob.perform_later(@boundary.id)
      audit_log("hdf_aggregation_enqueued", subject: @boundary)
      render json: { data: { status: "enqueued", authorization_boundary_id: @boundary.id } }, status: :accepted
    else
      result = HdfAggregationService.new(@boundary).aggregate
      audit_log("hdf_aggregation_run", subject: @boundary, metadata: result.to_h)
      render json: { data: { status: "aggregated", **result.to_h } }
    end
  end

  private

  def set_boundary
    key = params[:authorization_boundary_id]
    @boundary =
      if key.to_s.match?(/\A\d+\z/)
        AuthorizationBoundary.find(key)
      else
        AuthorizationBoundary.find_by!(slug: key)
      end
  end

  def authorize_write!
    return if current_user.admin?
    return if current_user.has_permission?("evidence.write", authorization_boundary_id: @boundary&.id)

    raise NotAuthorizedError, "Not authorized to aggregate findings"
  end
end
