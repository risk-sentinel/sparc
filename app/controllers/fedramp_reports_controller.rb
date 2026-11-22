# frozen_string_literal: true

# #1354 / #1384 — download the boundary's FedRAMP vulnerability reports from
# the triage page. A thin client over FedrampVulnerabilityReportService, the
# same service as the API (Api::V1::FedrampReportsController):
#
#   GET /authorization_boundaries/:id/triage/fedramp/vulnerability_detail_report  (VER-RPT-VDT)
#   GET /authorization_boundaries/:id/triage/fedramp/accepted_vulnerability_info  (VER-RPT-AVI)
#       [?from=&to=]  ISO 8601 dates or date-times; default the 30 days ending now
#   GET /authorization_boundaries/:id/triage/fedramp/historical_ver_activity      (VER-TFR-MRH, #1390)
#       [?from=&to=]  default the 12 months ending now
#   GET /authorization_boundaries/:id/triage/fedramp/certification_package_overview (FRC-CSO-PKG, #1390)
#   GET /authorization_boundaries/:id/fedramp/security_decision_record               (SDR-CSO-FRR, #1390)
#       from the boundary's FedRAMP page, which it returns to on a refusal
#
# A report that cannot be written (no package overview address, a bad
# period) or that fails its own validation is never sent; the triage page
# says why.
#
# NIST SP 800-53: RA-5, CA-7, CA-5, SI-2, AC-3 / AC-6 (evidence.read on the
# boundary), AU-12 (each download audited).
class FedrampReportsController < ApplicationController
  include RequiresFedramp

  before_action :set_boundary
  before_action :authorize_read!
  before_action :require_fedramp!

  def vulnerability_detail_report
    deliver(:vulnerability_detail_report, "fedramp_vulnerability_detail_report_exported", "vulnerabilities", "vdr")
  end

  def accepted_vulnerability_info
    deliver(:accepted_vulnerability_info, "fedramp_accepted_vulnerability_info_exported", "acceptedVulnerabilities", "avi")
  end

  def historical_ver_activity
    deliver(:historical_ver_activity, "fedramp_historical_ver_activity_exported",
            %w[activeVulnerabilities acceptedVulnerabilities], "ver-history")
  end

  def certification_package_overview
    doc = FedrampPackageOverviewService.call(@boundary)
    audit_log("fedramp_certification_package_overview_exported", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, contacts: doc["contactInformation"].size })
    send_document(doc, "package-overview")
  rescue FedrampVulnerabilityReportService::Error => e
    refuse(e)
  end

  def security_decision_record
    service = FedrampSecurityDecisionRecordService.new(@boundary)
    doc = service.call
    audit_log("fedramp_security_decision_record_exported", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, version: doc.dig("metadata", "version"),
                          requirements: doc["fedRampRequirements"].size, gaps: service.gaps.size })
    send_document(doc, "sdr")
  rescue FedrampVulnerabilityReportService::Error => e
    refuse(e, back: fedramp_authorization_boundary_path(@boundary))
  end

  private

  def send_document(doc, suffix)
    send_data JSON.pretty_generate(doc),
              filename: "#{@boundary.slug || @boundary.uuid}-fedramp-#{suffix}.json",
              type: "application/json", disposition: "attachment"
  end

  def refuse(error, back: triage_authorization_boundary_path(@boundary))
    if error.is_a?(FedrampVulnerabilityReportService::InvalidReport)
      messages = error.errors.first(3).map { |err| "#{err[:pointer]} #{err[:message]}".strip }
      redirect_to back, error: "SPARC produced an invalid report and did not send it: #{messages.join('; ')}"
    else
      redirect_to back, error: "FedRAMP report not produced: #{error.message}"
    end
  end

  def deliver(report, action, list_keys, suffix)
    doc = FedrampVulnerabilityReportService.public_send(report, @boundary, from: params[:from], to: params[:to])
    count = Array(list_keys).sum { |key| doc[key].size }
    audit_log(action, subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, vulnerabilities: count,
                          from: doc.dig("reportPeriod", "from"), to: doc.dig("reportPeriod", "to"),
                          generated_at: doc["generatedAt"] }.compact)
    send_document(doc, suffix)
  rescue FedrampVulnerabilityReportService::Error => e
    refuse(e)
  end

  def set_boundary
    key = params[:id]
    @boundary =
      if key.to_s.match?(/\A\d+\z/)
        AuthorizationBoundary.find(key)
      else
        AuthorizationBoundary.find_by!(slug: key)
      end
  end

  def authorize_read!
    authorize_permission!("evidence.read", authorization_boundary_id: @boundary.id)
  end
end
