# frozen_string_literal: true

# GET /api/v1/authorization_boundaries/:authorization_boundary_id/disposition_poam
#
# #1368 — the boundary's finding dispositions as an OSCAL POA&M, completed
# with NIST's vocabulary (DispositionPoamExportService) and schema-validated.
# Refused, with the reason, when a disposition lacks its NIST fields or the
# dispositions cannot be exported as HDF amendments.
#
# NIST 800-53: CA-5 (plan of action and milestones), AC-3 (evidence.read).
class Api::V1::DispositionPoamsController < Api::V1::BaseController
  before_action :set_boundary
  before_action :authorize_read!

  rescue_from DispositionPoamExportService::MissingNistFields do |e|
    render json: { error: "Dispositions lack the NIST POA&M fields", details: e.message,
                   missing_nist_fields: e.missing }, status: :unprocessable_content
  end
  # #1325 — nothing to export is a plain answer, as for the amendments.
  rescue_from HdfAmendmentExportService::NoDispositions do |e|
    render json: { error: e.message }, status: :unprocessable_content
  end
  rescue_from HdfAmendmentExportService::UnexportableDisposition do |e|
    render json: { error: "Dispositions cannot be exported as HDF amendments", details: e.message,
                   missing_expiry: e.missing_expiry, beyond_review_window: e.beyond_window },
           status: :unprocessable_content
  end
  # SPARC validates every OSCAL document it emits; an invalid one is a defect
  # in this export or in hdf's conversion, never returned.
  rescue_from OscalValidationError do |e|
    render json: { error: "The POA&M does not conform to the OSCAL schema and was not returned",
                   details: e.message.lines.map(&:strip).reject(&:empty?) }, status: :bad_gateway
  end
  rescue_from HdfRunner::Error do |e|
    render json: { error: "POA&M conversion failed", details: e.message }, status: :unprocessable_content
  end

  def show
    doc = DispositionPoamExportService.new(@boundary).export
    audit_log("disposition_poam_exported", subject: @boundary,
              metadata: { risks: Array(doc.dig("plan-of-action-and-milestones", "risks")).size })
    render json: doc
  end

  private

  def set_boundary
    key = params[:authorization_boundary_id]
    @boundary = key.to_s.match?(/\A\d+\z/) ? AuthorizationBoundary.find(key) : AuthorizationBoundary.find_by!(slug: key)
  end

  def authorize_read!
    return if current_user.instance_administrator?
    return if current_user.has_permission?("evidence.read", authorization_boundary_id: @boundary&.id)

    raise NotAuthorizedError, "Not authorized to export the POA&M"
  end
end
