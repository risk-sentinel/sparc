# frozen_string_literal: true

# #809 goal 2 — download the signed HDF package (amendments + findings +
# dispositions) for a boundary, for the consumer to archive / feed downstream.
#
#   GET /api/v1/authorization_boundaries/:authorization_boundary_id/hdf_package
#
# NIST 800-53: IA-2 (token auth), AC-3/AC-6 (boundary-scoped RBAC),
# AU-10 (signed bundle), AU-12 (audit).
class Api::V1::HdfPackagesController < Api::V1::BaseController
  before_action :set_boundary
  before_action :authorize_read!

  def show
    bundle = HdfPackageService.new(@boundary).build
    audit_log("hdf_package_exported", subject: @boundary,
              metadata: { findings: bundle["payload"]["findings"].size,
                          dispositions: bundle["payload"]["dispositions"].size })
    render json: bundle
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

  def authorize_read!
    return if current_user.admin?
    return if current_user.has_permission?("evidence.read", authorization_boundary_id: @boundary&.id)

    raise NotAuthorizedError, "Not authorized to export the HDF package"
  end
end
