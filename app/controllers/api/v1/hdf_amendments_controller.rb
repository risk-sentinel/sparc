# frozen_string_literal: true

# #447 — translation OUT. Export the boundary's triaged dispositions as an HDF
# Amendments document the tenant's CI pulls and applies:
#
#   GET /api/v1/authorization_boundaries/:authorization_boundary_id/hdf_amendments
#       [?verify=false]
#
# The response body IS the artefact (raw Amendments JSON, not wrapped) so it can
# be fed straight to `hdf amend apply`.
#
# NIST 800-53: IA-2 (token auth), AC-3/AC-6 (boundary-scoped RBAC),
# CA-7 (continuous monitoring), SI-2 (flaw remediation), AU-12 (audit).
class Api::V1::HdfAmendmentsController < Api::V1::BaseController
  before_action :set_boundary
  before_action :authorize_read!

  rescue_from HdfRunner::Error do |e|
    render json: { error: "Amendment verification failed", details: e.message },
           status: :unprocessable_entity
  end

  # GET .../hdf_amendments
  def show
    verify = params[:verify].to_s != "false"
    doc = HdfAmendmentExportService.new(@boundary).export(verify: verify)
    audit_log("hdf_amendments_exported", subject: @boundary,
              metadata: { overrides: doc["overrides"].size, verified: verify })
    render json: doc
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

    raise NotAuthorizedError, "Not authorized to export amendments"
  end
end
