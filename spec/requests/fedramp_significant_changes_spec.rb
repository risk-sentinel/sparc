# frozen_string_literal: true

require "rails_helper"

# #1390 — the Significant changes and Incidents tabs of the boundary's FedRAMP
# page (FedrampSignificantChangesController, FedrampIncidentsController).
RSpec.describe "Boundary FedRAMP changes and incidents", type: :request do
  let(:boundary) { create(:authorization_boundary, :fedramp, fedramp_package_overview_uri: "https://trust.example/cpo.json") }

  def user_with(permissions, on: boundary)
    user = create(:user)
    role = create(:role, :authorization_boundary_scoped, permissions: permissions)
    create(:user_role, user: user, role: role, authorization_boundary_id: on.id)
    user
  end

  def html = Nokogiri::HTML(response.body)

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "significant changes" do
    let(:writer) { user_with({ "evidence.read" => true, "evidence.write" => true }) }
    let(:changes_path) { fedramp_significant_changes_authorization_boundary_path(boundary) }

    it "records a change from the form as rendered, lists it, and audits it" do
      sign_in_as(writer)
      get changes_path
      form = html.at_css("[data-testid='fedramp-change-form']")
      expect(form["action"]).to eq(changes_path)
      expect(html.at_css("[data-testid='fedramp-tab-changes']")["class"]).to include("active")
      expect(html.at_css("[data-testid='fedramp-tab-incidents']")).to be_nil # no incident.read

      expect {
        post changes_path, params: { milestones_listed: "1",
                                     fedramp_significant_change: { change_type: "Adaptive", description: "New dashboard",
                                                                   plan_summary: "Behind a flag", finished_on: "2026-11-20",
                                                                   milestones: [ { description: "Beta", target_date: "2026-11-18" } ] } }
      }.to change { AuditEvent.where(action: "fedramp_significant_change_recorded").count }.by(1)
      change = boundary.fedramp_significant_changes.sole
      expect(response).to redirect_to(fedramp_significant_change_authorization_boundary_path(boundary, change))
      expect(change).to have_attributes(change_type: "Adaptive", created_by: writer,
                                        milestones: [ { "description" => "Beta", "target_date" => "2026-11-18" } ])

      get changes_path
      expect(html.css("[data-testid='fedramp-change-row']").map { |r| r["data-change"] }).to eq([ change.uuid ])
    end

    it "shows the notices with when each is due, records one sent, and downloads the notification" do
      sign_in_as(writer)
      change = FedrampSignificantChangeService.new(boundary).record(
        attributes: { change_type: "Adaptive", description: "New dashboard", finished_on: "2026-11-20" }, user: writer
      ).change
      path = fedramp_significant_change_authorization_boundary_path(boundary, change)
      get path
      row = html.at_css("[data-testid='fedramp-change-deadline'][data-stage='after_finish']")
      expect(row.text).to include("SCN-ADP-NTF", "2026-12-07", "10 business days")

      form = row.at_css("[data-testid='fedramp-change-notice-form']")
      post form["action"], params: { stage: "after_finish", sent_on: Date.current.iso8601 }
      expect(response).to redirect_to(path)
      expect(change.reload.notice_for("after_finish")).to include("sent_on" => Date.current.iso8601, "recorded_by_id" => writer.id)
      expect(AuditEvent.where(action: "fedramp_significant_change_notice_recorded").count).to eq(1)

      get fedramp_significant_change_notification_authorization_boundary_path(boundary, change)
      expect(response.headers["Content-Disposition"]).to include("attachment")
      expect(JSON.parse(response.body)).to include("changeType" => "Adaptive")
      expect(AuditEvent.where(action: "fedramp_significant_change_notification_exported").count).to eq(1)
    end

    it "explains a routine change needs no notification" do
      sign_in_as(writer)
      change = FedrampSignificantChangeService.new(boundary).record(
        attributes: { change_type: "Routine", description: "Patching" }, user: writer
      ).change
      get fedramp_significant_change_authorization_boundary_path(boundary, change)
      expect(html.at_css("[data-testid='fedramp-change-routine']")).to be_present
      get fedramp_significant_change_notification_authorization_boundary_path(boundary, change)
      expect(flash[:error]).to include("SCN-RTR-NNR")
    end

    it "says why a change is not recorded" do
      sign_in_as(writer)
      post changes_path, params: { fedramp_significant_change: { change_type: "Adaptive", description: "" } }
      expect(response).to redirect_to(changes_path)
      expect(flash[:error]).to include("Description can't be blank")
    end

    it "is read-only without evidence.write, refused without evidence.read, and off with FedRAMP" do
      sign_in_as(user_with({ "evidence.read" => true }))
      get changes_path
      expect(html.at_css("[data-testid='fedramp-change-form']")).to be_nil
      post changes_path, params: { fedramp_significant_change: { change_type: "Adaptive", description: "x" } }
      expect(boundary.fedramp_significant_changes).to be_empty

      sign_in_as(user_with({ "incident.read" => true }))
      get changes_path
      expect(response).to redirect_to(root_path)

      boundary.update!(fedramp_enabled: false)
      sign_in_as(create(:user, :admin))
      get changes_path
      expect(response).to redirect_to(authorization_boundary_path(boundary))
    end
  end

  describe "incidents" do
    let(:responder) { user_with({ "incident.read" => true, "incident.write" => true }) }
    let(:incidents_path) { fedramp_incidents_authorization_boundary_path(boundary) }

    it "records an incident from the form as rendered, with its timeline and rating" do
      sign_in_as(responder)
      get incidents_path
      expect(html.at_css("[data-testid='fedramp-incident-form']")["action"]).to eq(incidents_path)
      expect {
        post incidents_path, params: { milestones_listed: "1",
                                       fedramp_incident: { tracking_id: "INC-7", reportable: "1", description: "Phishing",
                                                           detected_at: "2026-11-20T09:00", current_rating: "2",
                                                           affected_agencies: "DHS\nGSA",
                                                           milestones: [ { occurred_at: "2026-11-20T09:30", description: "Contained" } ] } }
      }.to change { AuditEvent.where(action: "fedramp_incident_recorded").count }.by(1)
      incident = boundary.fedramp_incidents.sole
      expect(response).to redirect_to(fedramp_incident_authorization_boundary_path(boundary, incident))
      expect(incident).to have_attributes(tracking_id: "INC-7", current_rating: 2, affected_agencies: %w[DHS GSA],
                                          detected_at: Time.utc(2026, 11, 20, 9))
      expect(incident.milestones).to eq([ { "occurred_at" => "2026-11-20T09:30:00Z", "description" => "Contained" } ])
    end

    it "shows the report deadlines, records a report sent, and downloads each report" do
      sign_in_as(responder)
      incident = FedrampIncidentService.new(boundary).record(
        attributes: { tracking_id: "INC-8", evaluation_completed_at: 2.hours.ago, current_rating: "1" }, user: responder
      ).incident
      path = fedramp_incident_authorization_boundary_path(boundary, incident)
      get path
      initial = html.at_css("[data-testid='fedramp-incident-deadline'][data-report-type='Initial']")
      expect(initial.text).to include("IEC-CSO-IIR", "MUST", "1 business day")
      expect(html.at_css("[data-testid='fedramp-incident-download-final']")).to be_nil # not resolved

      post fedramp_incident_reports_authorization_boundary_path(boundary, incident),
           params: { report_type: "Initial", sent_at: 1.hour.ago.utc.strftime("%Y-%m-%dT%H:%M") }
      expect(response).to redirect_to(path)
      expect(incident.reload.reports_of("Initial").size).to eq(1)
      expect(AuditEvent.where(action: "fedramp_incident_report_recorded").count).to eq(1)

      get fedramp_incident_report_authorization_boundary_path(boundary, incident, type: "Ongoing")
      expect(JSON.parse(response.body)).to include("reportType" => "Ongoing", "providerTrackingId" => "INC-8")
      expect(AuditEvent.where(action: "fedramp_incident_report_exported").count).to eq(1)
    end

    it "needs incident.read, which evidence.* does not give, and the tab shows only with it" do
      sign_in_as(user_with({ "evidence.read" => true, "evidence.write" => true }))
      get incidents_path
      expect(response).to redirect_to(root_path)

      sign_in_as(user_with({ "incident.read" => true }))
      get incidents_path
      expect(response).to have_http_status(:ok)
      expect(html.at_css("[data-testid='fedramp-tab-incidents']")).to be_present
      expect(html.at_css("[data-testid='fedramp-incident-form']")).to be_nil
      post incidents_path, params: { fedramp_incident: { tracking_id: "INC-9" } }
      expect(boundary.fedramp_incidents).to be_empty
    end
  end
end
