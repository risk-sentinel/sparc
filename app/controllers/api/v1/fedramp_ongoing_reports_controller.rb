# frozen_string_literal: true

# #1390 — a boundary's FedRAMP Ongoing Certification Reports (CCM-OCR-AVL):
#
#   GET  /api/v1/authorization_boundaries/:id/fedramp_ongoing_reports
#        the reports issued (without their documents) and when the next is due
#   GET  .../fedramp_ongoing_reports/draft[?from&to&recommendations[]&other_changes[]&other_planned[]]
#        the report for a period, validated; the period defaults to the day
#        after the last report issued (or 3 months back) through today
#   POST .../fedramp_ongoing_reports   { fedramp_ongoing_report: { from, to, recommendations, ... } }
#        (every field optional)
#        issue it: kept exactly as issued (201)
#   GET  .../fedramp_ongoing_reports/:report_id
#        one report as issued, with its document
#
# The report summarizes the boundary's reportable incidents, so reading needs
# incident.read as well as evidence.read, and issuing evidence.write with
# incident.read, or an instance administrator. 422 when FedRAMP is not
# enabled for the boundary, for a bad period, or a period starting on or
# before the end of one already issued.
#
# NIST SP 800-53: CA-7, AC-3 / AC-6, AU-12.
class Api::V1::FedrampOngoingReportsController < Api::V1::BaseController
  include FedrampApiResource

  before_action :set_boundary
  before_action :authorize_read!
  before_action :authorize_write!, only: :create
  before_action :require_fedramp!

  rescue_from FedrampOngoingReportService::Error, FedrampVulnerabilityReportService::MissingPackageOverview,
              FedrampVulnerabilityReportService::InvalidPeriod do |e|
    render json: { error: e.message }, status: :unprocessable_content
  end

  rescue_from FedrampVulnerabilityReportService::InvalidReport do |e|
    render json: { error: e.message, errors: e.errors }, status: :bad_gateway
  end

  def index
    reports = service.reports.to_a
    render json: { data: reports.map { |r| serialize(r) },
                   meta: { total: reports.size, next_target_date: service.next_target_date&.iso8601,
                           default_period: service.default_period.map(&:iso8601) } }
  end

  def draft
    doc = service.build(service.input(**query_input))
    audit_log("fedramp_ongoing_report_exported", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, issued: false, from: doc.dig("reportPeriod", "from"),
                          to: doc.dig("reportPeriod", "to") })
    render json: doc
  end

  def create
    report = service.issue(service.input(**issue_input), user: current_user)
    audit_log("fedramp_ongoing_report_issued", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, report: report.uuid, from: report.period_from.iso8601,
                          to: report.period_to.iso8601, sha256: report.sha256 })
    render json: { data: serialize(report, document: true) }, status: :created
  end

  def show
    render json: { data: serialize(service.find!(params[:report_id]), document: true) }
  end

  private

  def service = (@service ||= FedrampOngoingReportService.new(@boundary))

  # Every field is optional: an empty body issues the default period.
  def issue_input
    return {} if params[:fedramp_ongoing_report].blank?

    permit_strictly(:fedramp_ongoing_report, :from, :to, recommendations: [], other_changes: [], other_planned: [])
      .to_h.symbolize_keys
  end

  # The draft's query: two dates and three lists of text, each read as text
  # (a nested value is refused by the service as a bad date or line).
  def query_input
    input = %i[from to].to_h { |k| [ k, params[k].is_a?(String) ? params[k] : nil ] }
    %i[recommendations other_changes other_planned].each do |k|
      input[k] = Array(params[k]).select { |v| v.is_a?(String) }
    end
    input
  end

  def serialize(report, document: false)
    data = { uuid: report.uuid, period_from: report.period_from.iso8601, period_to: report.period_to.iso8601,
             recommendations: report.recommendations, sha256: report.sha256, issued_by_id: report.issued_by_id,
             issued_at: report.created_at.utc.iso8601 }
    document ? data.merge(document: report.document) : data
  end

  def authorize_read!
    authorize_boundary_permission!("evidence.read", "Not authorized to read this boundary's FedRAMP reports")
    authorize_boundary_permission!("incident.read", "Not authorized to read this boundary's FedRAMP incidents")
  end

  def authorize_write!
    authorize_boundary_permission!("evidence.write", "Not authorized to issue this boundary's FedRAMP reports")
  end
end
