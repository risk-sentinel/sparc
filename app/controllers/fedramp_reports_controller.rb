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
#
# A report that cannot be written (no package overview address, a bad
# period) or that fails its own validation is never sent; the triage page
# says why.
#
# NIST SP 800-53: RA-5, CA-7, CA-5, SI-2, AC-3 / AC-6 (evidence.read on the
# boundary), AU-12 (each download audited).
class FedrampReportsController < ApplicationController
  before_action :set_boundary
  before_action :authorize_read!

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

  private

  def deliver(report, action, list_keys, suffix)
    doc = FedrampVulnerabilityReportService.public_send(report, @boundary, from: params[:from], to: params[:to])
    count = Array(list_keys).sum { |key| doc[key].size }
    audit_log(action, subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, vulnerabilities: count,
                          from: doc.dig("reportPeriod", "from"), to: doc.dig("reportPeriod", "to"),
                          generated_at: doc["generatedAt"] }.compact)
    send_data JSON.pretty_generate(doc),
              filename: "#{@boundary.slug || @boundary.uuid}-fedramp-#{suffix}.json",
              type: "application/json", disposition: "attachment"
  rescue FedrampVulnerabilityReportService::InvalidReport => e
    messages = e.errors.first(3).map { |err| "#{err[:pointer]} #{err[:message]}".strip }
    redirect_to triage_authorization_boundary_path(@boundary),
                error: "SPARC produced an invalid report and did not send it: #{messages.join('; ')}"
  rescue FedrampVulnerabilityReportService::Error => e
    redirect_to triage_authorization_boundary_path(@boundary), error: "FedRAMP report not produced: #{e.message}"
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
