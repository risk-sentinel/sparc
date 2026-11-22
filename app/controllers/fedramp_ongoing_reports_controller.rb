# frozen_string_literal: true

# #1390 — the Ongoing reports tab of the boundary's FedRAMP page: the
# Ongoing Certification Report (CCM-OCR-AVL) for a period, shown in
# human-readable form and downloadable as JSON, and every report issued, kept
# as issued. A thin client of FedrampOngoingReportService, the same service
# as Api::V1::FedrampOngoingReportsController.
#
#   GET  /authorization_boundaries/:id/fedramp/ongoing_reports[?from&to&recommendations...]
#   GET  /authorization_boundaries/:id/fedramp/ongoing_reports/draft      the JSON for the period
#   POST /authorization_boundaries/:id/fedramp/ongoing_reports            issue it
#   GET  /authorization_boundaries/:id/fedramp/ongoing_reports/:report_id
#   GET  /authorization_boundaries/:id/fedramp/ongoing_reports/:report_id/document
#
# The report summarizes the boundary's reportable incidents, so reading needs
# incident.read as well as evidence.read, and issuing evidence.write with
# incident.read. FedRAMP must be turned on for the boundary.
#
# NIST SP 800-53: CA-7, AC-3 / AC-6, AU-12 (each issue and download audited).
class FedrampOngoingReportsController < ApplicationController
  include FedrampPage

  INPUT_KEYS = %i[from to recommendations other_changes other_planned].freeze

  before_action :set_boundary
  before_action :authorize_read!
  before_action :authorize_write!, only: :create
  before_action :require_fedramp!

  def index
    @reports = service.reports.to_a
    @next_target = service.next_target_date
    @may_issue = boundary_permission?("evidence.write")
    @input = service.input(**input_params)
    @document = service.build(@input) if @boundary.fedramp_overview_address.present?
  rescue FedrampOngoingReportService::Error, FedrampVulnerabilityReportService::Error => e
    @input ||= service.input
    @error = e.message
  end

  def draft
    doc = service.build(service.input(**input_params))
    audit_log("fedramp_ongoing_report_exported", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, issued: false, from: doc.dig("reportPeriod", "from"),
                          to: doc.dig("reportPeriod", "to") })
    send_document(doc, "draft-#{doc.dig('reportPeriod', 'to')}")
  rescue FedrampOngoingReportService::Error, FedrampVulnerabilityReportService::Error => e
    redirect_to fedramp_ongoing_reports_authorization_boundary_path(@boundary), error: "Report not produced: #{e.message}"
  end

  def create
    report = service.issue(service.input(**input_params), user: current_user)
    audit_log("fedramp_ongoing_report_issued", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, report: report.uuid, from: report.period_from.iso8601,
                          to: report.period_to.iso8601, sha256: report.sha256 })
    redirect_to fedramp_ongoing_report_authorization_boundary_path(@boundary, report),
                success: "Issued the Ongoing Certification Report for #{report.period_from} to #{report.period_to}."
  rescue FedrampOngoingReportService::Error, FedrampVulnerabilityReportService::Error => e
    redirect_to fedramp_ongoing_reports_authorization_boundary_path(@boundary, input_params),
                error: "Report not issued: #{e.message}"
  end

  def show
    @report = service.find!(params[:report_id])
  end

  def document
    report = service.find!(params[:report_id])
    audit_log("fedramp_ongoing_report_exported", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, issued: true, report: report.uuid })
    send_document(report.document, report.period_to.iso8601)
  end

  private

  def service = (@service ||= FedrampOngoingReportService.new(@boundary))

  def input_params = params.permit(*INPUT_KEYS).to_h.symbolize_keys

  def send_document(doc, suffix)
    send_data JSON.pretty_generate(doc), filename: "#{@boundary.slug || @boundary.uuid}-fedramp-ocr-#{suffix}.json",
                                         type: "application/json", disposition: "attachment"
  end

  def authorize_read!
    authorize_permission!("evidence.read", authorization_boundary_id: @boundary.id)
    authorize_permission!("incident.read", authorization_boundary_id: @boundary.id)
  end

  def authorize_write!
    authorize_permission!("evidence.write", authorization_boundary_id: @boundary.id)
  end
end
