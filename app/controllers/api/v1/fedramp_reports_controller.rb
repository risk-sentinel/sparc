# frozen_string_literal: true

# #1354 / #1384 — the boundary's FedRAMP vulnerability reports, written by
# FedrampVulnerabilityReportService:
#
#   GET /api/v1/authorization_boundaries/:id/fedramp/vulnerability_detail_report  (VER-RPT-VDT)
#   GET /api/v1/authorization_boundaries/:id/fedramp/accepted_vulnerability_info  (VER-RPT-AVI)
#       [?from=ISO8601&to=ISO8601]   default: the 30 days ending now
#   GET /api/v1/authorization_boundaries/:id/fedramp/historical_ver_activity      (VER-TFR-MRH, #1390)
#       [?from=ISO8601&to=ISO8601]   default: the 12 months ending now
#   GET /api/v1/authorization_boundaries/:id/fedramp/certification_package_overview (FRC-CSO-PKG, #1390)
#       written by FedrampPackageOverviewService; names no overview address
#
# The response body IS the FedRAMP document (not wrapped), with `$schema`
# naming the FedRAMP schema it validates against.
#
#   422 — the boundary has no FedRAMP Certification Package Overview address,
#         or the period is not usable; for the overview, the boundary does not
#         yet record a field it requires (the message lists them);
#   502 — SPARC built a report that fails its own FedRAMP schema or
#         completeness check. It is never returned: the fault is SPARC's, not
#         the caller's (as Api::V1::TranslationsController refuses invalid OSCAL).
#
# Permission: `evidence.read` on the boundary, or an instance administrator.
# Each download is audited.
#
# NIST SP 800-53: RA-5, CA-7, CA-5, SI-2 (the reports), AC-3 / AC-6
# (boundary-scoped permission), AU-12 (each download audited).
class Api::V1::FedrampReportsController < Api::V1::BaseController
  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  before_action :set_boundary
  before_action :authorize_read!

  rescue_from FedrampVulnerabilityReportService::MissingPackageOverview,
              FedrampVulnerabilityReportService::InvalidPeriod,
              FedrampPackageOverviewService::Incomplete do |e|
    render json: { error: e.message }, status: :unprocessable_content
  end

  rescue_from FedrampVulnerabilityReportService::InvalidReport do |e|
    render json: {
      error: "SPARC produced an invalid report",
      document_type: e.document_type,
      details: e.errors,
      note: "SPARC validates every FedRAMP report it writes against the pinned FedRAMP schema and will not " \
            "return an invalid one. This is a defect in SPARC, not in the request."
    }, status: :bad_gateway
  end

  # GET .../fedramp/vulnerability_detail_report
  def vulnerability_detail_report
    doc = FedrampVulnerabilityReportService.vulnerability_detail_report(@boundary, from: params[:from], to: params[:to])
    audit("fedramp_vulnerability_detail_report_exported", doc, doc["vulnerabilities"].size)
    render json: doc
  end

  # GET .../fedramp/accepted_vulnerability_info
  def accepted_vulnerability_info
    doc = FedrampVulnerabilityReportService.accepted_vulnerability_info(@boundary, from: params[:from], to: params[:to])
    audit("fedramp_accepted_vulnerability_info_exported", doc, doc["acceptedVulnerabilities"].size)
    render json: doc
  end

  # GET .../fedramp/historical_ver_activity
  def historical_ver_activity
    doc = FedrampVulnerabilityReportService.historical_ver_activity(@boundary, from: params[:from], to: params[:to])
    count = doc["activeVulnerabilities"].size + doc["acceptedVulnerabilities"].size
    audit("fedramp_historical_ver_activity_exported", doc, count)
    render json: doc
  end

  # GET .../fedramp/certification_package_overview
  def certification_package_overview
    doc = FedrampPackageOverviewService.call(@boundary)
    audit_log("fedramp_certification_package_overview_exported", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, contacts: doc["contactInformation"].size })
    render json: doc
  end

  private

  # The historical activity carries no reportPeriod; its generatedAt is
  # recorded instead.
  def audit(action, doc, count)
    audit_log(action, subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, vulnerabilities: count,
                          from: doc.dig("reportPeriod", "from"), to: doc.dig("reportPeriod", "to"),
                          generated_at: doc["generatedAt"] }.compact)
  end

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

    raise NotAuthorizedError, "Not authorized to read this boundary's FedRAMP reports"
  end
end
