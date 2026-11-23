# frozen_string_literal: true

# #1390 — the Incidents tab of the boundary's FedRAMP page: every incident
# the provider evaluated, when each Incident Report is due, and the report
# itself (Initial, Ongoing, Final). A thin client of FedrampIncidentService,
# the same service as Api::V1::FedrampIncidentsController.
#
#   GET   /authorization_boundaries/:id/fedramp/incidents
#   POST  /authorization_boundaries/:id/fedramp/incidents
#   GET   /authorization_boundaries/:id/fedramp/incidents/:incident_id
#   PATCH /authorization_boundaries/:id/fedramp/incidents/:incident_id
#   GET   /authorization_boundaries/:id/fedramp/incidents/:incident_id/report?type=Initial|Ongoing|Final
#   POST  /authorization_boundaries/:id/fedramp/incidents/:incident_id/reports
#
# Incidents are sensitive: reading needs incident.read on the boundary,
# recording incident.write. FedRAMP must be turned on for the boundary.
#
# NIST SP 800-53: IR-4, IR-6, AC-3 / AC-6, AU-12 (each change audited).
class FedrampIncidentsController < ApplicationController
  include FedrampPage

  READ_PERMISSION = "incident.read"
  WRITE_PERMISSION = "incident.write"

  before_action :set_boundary
  before_action :authorize_read!, only: %i[index show report]
  before_action :authorize_write!, only: %i[create update record_report]
  before_action :require_fedramp!
  before_action :set_incident, only: %i[show update report record_report]

  def index
    @incidents = service.incidents.to_a
    @incident = @boundary.fedramp_incidents.new
    @may_edit = boundary_permission?(WRITE_PERMISSION)
  end

  def show
    @deadlines = service.deadlines(@incident)
    @no_deadlines = service.no_deadlines_reason(@incident)
    @may_edit = boundary_permission?(WRITE_PERMISSION)
  end

  def create
    result = service.record(attributes: incident_params, user: current_user)
    audit(result)
    redirect_to fedramp_incident_authorization_boundary_path(@boundary, result.incident),
                success: "Recorded incident #{result.incident.tracking_id}."
  rescue FedrampIncidentService::Error => e
    redirect_to fedramp_incidents_authorization_boundary_path(@boundary), error: "Incident not recorded: #{e.message}"
  end

  def update
    result = service.record(incident: @incident, attributes: incident_params, user: current_user)
    audit(result)
    redirect_to fedramp_incident_authorization_boundary_path(@boundary, @incident), success: "Saved the incident."
  rescue FedrampIncidentService::Error => e
    redirect_to fedramp_incident_authorization_boundary_path(@boundary, @incident), error: "Incident not saved: #{e.message}"
  end

  def report
    doc = service.report(@incident, params[:type])
    audit_log("fedramp_incident_report_exported", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, incident: @incident.uuid, report_type: doc["reportType"] })
    send_data JSON.pretty_generate(doc),
              filename: "#{@boundary.slug || @boundary.uuid}-fedramp-incident-#{@incident.uuid}-#{doc['reportType'].downcase}.json",
              type: "application/json", disposition: "attachment"
  rescue FedrampIncidentService::Error, FedrampVulnerabilityReportService::Error => e
    redirect_to fedramp_incident_authorization_boundary_path(@boundary, @incident), error: "Report not produced: #{e.message}"
  end

  def record_report
    entry = service.record_report(@incident, type: params[:report_type], sent_at: params[:sent_at], user: current_user)
    audit_log("fedramp_incident_report_recorded", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, incident: @incident.uuid,
                          report_type: entry["report_type"], sent_at: entry["sent_at"], sha256: entry["sha256"] })
    redirect_to fedramp_incident_authorization_boundary_path(@boundary, @incident),
                success: "Recorded the #{entry['report_type'].downcase} report sent."
  rescue FedrampIncidentService::Error, FedrampVulnerabilityReportService::Error => e
    redirect_to fedramp_incident_authorization_boundary_path(@boundary, @incident), error: "Report not recorded: #{e.message}"
  end

  private

  def service = (@service ||= FedrampIncidentService.new(@boundary))

  def set_incident
    @incident = service.find!(params[:incident_id])
  end

  def incident_params
    params.fetch(:fedramp_incident, {})
          .permit(*(FedrampIncidentService::FIELDS - %w[milestones]), milestones: FedrampIncident::MILESTONE_KEYS).to_h
          .tap { |h| h["milestones"] = [] if params[:milestones_listed].present? && !h.key?("milestones") }
  end

  def audit(result)
    audit_log("fedramp_incident_recorded", subject: @boundary,
              metadata: { authorization_boundary_id: @boundary.id, incident: result.incident.uuid,
                          tracking_id: result.incident.tracking_id, created: result.created, changed: result.changes })
  end

  def authorize_read!
    authorize_permission!(READ_PERMISSION, authorization_boundary_id: @boundary.id)
  end

  def authorize_write!
    authorize_permission!(WRITE_PERMISSION, authorization_boundary_id: @boundary.id)
  end
end
