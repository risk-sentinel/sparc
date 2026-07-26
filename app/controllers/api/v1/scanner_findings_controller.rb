# frozen_string_literal: true

# #447 — list/show ingested scanner findings.
#
#   GET /api/v1/authorization_boundaries/:authorization_boundary_id/scanner_findings
#         ?status=failed&severity=HIGH
#   GET /api/v1/scanner_findings/:id   (uuid; flat)
#
# The list is the triage worklist (filter to status=failed to see what needs a
# disposition). Each finding surfaces its current disposition kind, if any.
#
# NIST 800-53: IA-2 (token auth), AC-3/AC-6 (boundary-scoped RBAC), CA-7 (monitoring).
class Api::V1::ScannerFindingsController < Api::V1::BaseController
  before_action :set_boundary, only: %i[index]
  before_action :set_finding,  only: %i[show]
  before_action :authorize_read!

  # GET .../scanner_findings
  def index
    scope = @boundary.scanner_findings
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where(severity: params[:severity].to_s.upcase) if params[:severity].present?
    scope = scope.order(:control_id)

    result = paginate(scope)
    render json: { data: result[:data].map { |f| serialize(f) }, meta: result[:meta] }
  end

  # GET /scanner_findings/:id
  def show
    render json: { data: serialize(@finding, detailed: true) }
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

  def set_finding
    @finding = ScannerFinding.find_by!(uuid: params[:id])
    @boundary = @finding.authorization_boundary
  end

  def serialize(finding, detailed: false)
    disposition = finding.disposition
    data = {
      id: finding.id,
      uuid: finding.uuid,
      control_id: finding.control_id,
      status: finding.status,
      severity: finding.severity,
      title: finding.title,
      scanner: finding.scanner,
      authorization_boundary_id: finding.authorization_boundary_id,
      scan_run_id: finding.scan_run_id,
      disposition_kind: disposition&.kind,
      created_at: finding.created_at.utc.iso8601
    }
    if detailed
      data[:description] = finding.description
      data[:raw_hdf] = finding.raw_hdf
      data[:updated_at] = finding.updated_at.utc.iso8601
    end
    data
  end

  def authorize_read!
    return if current_user.admin?
    return if current_user.has_permission?("evidence.read", authorization_boundary_id: @boundary&.id)

    raise NotAuthorizedError, "Not authorized to view scanner findings"
  end
end
