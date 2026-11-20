# frozen_string_literal: true

# #1354 — GET /api/v1/authorization_boundaries/:id/exchange_index
#
# What the boundary serves back out to the systems it exchanges with: its
# SPARC exports (SSP, SAP, SAR, POA&M, the CDEFs it uses, its HDF system
# document) and every received document it has ACCEPTED, each with its
# format, document type, update time, SHA-256 where SPARC holds fixed bytes,
# and its download URL (ExchangeIndexService). The downloads are the existing
# authenticated endpoints, each checking its own permission.
#
# The other system reads this with a service-account token scoped to the
# boundary. Permission: `evidence.read` on the boundary, or an instance
# administrator. Each read is audited with who and when (FedRAMP CDS-TRC-ACL
# access logs, CDS-TRC-AAI access inventory).
#
# NIST SP 800-53: CA-3 (information exchange), AC-3 / AC-6, AU-12.
class Api::V1::ExchangeIndexesController < Api::V1::BaseController
  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  before_action :set_boundary
  before_action :authorize_read!

  def show
    index = ExchangeIndexService.call(@boundary)
    audit_log("exchange_index_served", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, documents: index[:documents].size,
                          received: index[:documents].count { |d| d[:origin] == "received" } })
    render json: { data: index }
  end

  private

  def set_boundary
    key = params[:id].to_s
    @boundary =
      if key.match?(/\A\d+\z/)
        AuthorizationBoundary.find(key)
      elsif key.match?(UUID_FORMAT)
        AuthorizationBoundary.find_by(uuid: key.downcase) || AuthorizationBoundary.find_by!(slug: key)
      else
        AuthorizationBoundary.find_by!(slug: key)
      end
  end

  def authorize_read!
    return if current_user.instance_administrator?
    return if current_user.has_permission?("evidence.read", authorization_boundary_id: @boundary.id)

    raise NotAuthorizedError, "Not authorized to read this boundary's exchange index"
  end
end
