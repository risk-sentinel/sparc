# frozen_string_literal: true

# #1390 — a boundary's FedRAMP incidents (FedrampIncident):
#
#   GET  /api/v1/authorization_boundaries/:id/fedramp_incidents
#   POST /api/v1/authorization_boundaries/:id/fedramp_incidents
#   GET  /api/v1/authorization_boundaries/:id/fedramp_incidents/:incident_id
#   PUT  /api/v1/authorization_boundaries/:id/fedramp_incidents/:incident_id
#        only the fields sent change; current_rating adds an N-rating to the history
#   GET  .../fedramp_incidents/:incident_id/report?type=Initial|Ongoing|Final
#        the Incident Report (IEC-CSO-IIR / OIR / FIR), validated
#   POST .../fedramp_incidents/:incident_id/reports   { report_type, sent_at }
#        records a report sent, with the report as it stood
#
# Each incident carries when each report is due, by the boundary's class and
# the incident's N-rating. 422 when FedRAMP is not enabled for the boundary,
# for a value the record does not allow, for a report of an incident that is
# not reportable, or a Final report before resolution. Incidents are
# sensitive: reading needs incident.read on the boundary, recording
# incident.write, or an instance administrator. Each change is audited.
#
# NIST SP 800-53: IR-4, IR-6, AC-3 / AC-6, AU-12.
class Api::V1::FedrampIncidentsController < Api::V1::BaseController
  include FedrampApiResource

  before_action :set_boundary
  before_action :authorize_read!, only: %i[index show report]
  before_action :authorize_write!, only: %i[create update record_report]
  before_action :require_fedramp!
  before_action :set_incident, only: %i[show update report record_report]

  rescue_from FedrampIncidentService::Error do |e|
    render json: { error: e.message }, status: :unprocessable_content
  end

  rescue_from FedrampVulnerabilityReportService::MissingPackageOverview do |e|
    render json: { error: e.message }, status: :unprocessable_content
  end

  rescue_from FedrampVulnerabilityReportService::InvalidReport do |e|
    render json: { error: e.message, errors: e.errors }, status: :bad_gateway
  end

  def index
    incidents = service.incidents.to_a
    render json: { data: incidents.map { |i| serialize(i) },
                   meta: { total: incidents.size, unresolved: incidents.count { |i| !i.resolved? } } }
  end

  def show
    render json: { data: serialize(@incident) }
  end

  def create
    result = service.record(attributes: incident_params, user: current_user)
    audit(result)
    render json: { data: serialize(result.incident) }, status: :created
  end

  def update
    result = service.record(incident: @incident, attributes: incident_params, user: current_user)
    audit(result)
    render json: { data: serialize(result.incident) }
  end

  def report
    doc = service.report(@incident, params[:type])
    audit_log("fedramp_incident_report_exported", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, incident: @incident.uuid, report_type: doc["reportType"] })
    render json: doc
  end

  def record_report
    body = permit_strictly(:report, :report_type, :sent_at)
    entry = service.record_report(@incident, type: body[:report_type], sent_at: body[:sent_at], user: current_user)
    audit_log("fedramp_incident_report_recorded", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, incident: @incident.uuid,
                          report_type: entry["report_type"], sent_at: entry["sent_at"], sha256: entry["sha256"] })
    render json: { data: serialize(@incident.reload) }, status: :created
  end

  private

  def service = (@service ||= FedrampIncidentService.new(@boundary))

  def set_incident
    @incident = service.find!(params[:incident_id])
  end

  def incident_params
    # FedrampIncidentService::FIELDS, spelled out so bin/api_postman_check.rb
    # can read the body this endpoint takes.
    permit_strictly(:fedramp_incident, :tracking_id, :reportable, :coordinator, :description, :started_at,
                    :detected_at, :detection_source, :evaluation_completed_at, :current_rating, :evaluation_notes,
                    :functional_impact, :recovery_plan, :observed_activity, :root_cause, :response_activities,
                    :resolved_at, affected_agencies: [], indicators: [], related_cve_ids: [], lessons_learned: [],
                    milestones: FedrampIncident::MILESTONE_KEYS).to_h
  end

  def serialize(incident)
    incident.as_json(only: %w[uuid tracking_id reportable coordinator description started_at detected_at
                              detection_source evaluation_completed_at milestones ratings evaluation_notes
                              functional_impact recovery_plan affected_agencies observed_activity indicators
                              related_cve_ids root_cause response_activities resolved_at lessons_learned
                              created_at updated_at created_by_id updated_by_id])
            .merge("current_rating" => incident.current_rating,
                   "reports" => Array(incident.reports).map { |r| r.except("document") },
                   "deadlines_unavailable" => service.no_deadlines_reason(incident),
                   "deadlines" => service.deadlines(incident).map do |d|
                     { report_type: d.report_type, rule_id: d.rule_id, due_at: d.due_at&.utc&.iso8601,
                       timeframe: d.timeframe, force: d.force, status: d.status }
                   end)
  end

  def audit(result)
    audit_log("fedramp_incident_recorded", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, incident: result.incident.uuid,
                          tracking_id: result.incident.tracking_id, created: result.created, changed: result.changes })
  end

  def authorize_read!
    authorize_boundary_permission!("incident.read", "Not authorized to read this boundary's FedRAMP incidents")
  end

  def authorize_write!
    authorize_boundary_permission!("incident.write", "Not authorized to record this boundary's FedRAMP incidents")
  end
end
