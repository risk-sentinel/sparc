# frozen_string_literal: true

require "rails_helper"

# #1354 / #1384 — the triage page's FedRAMP report downloads
# (FedrampReportsController): the same service as the API, evidence.read on
# the boundary, each download audited, never an invalid report.
RSpec.describe "FedRAMP report downloads", type: :request do
  let(:boundary) { create(:authorization_boundary, fedramp_package_overview_uri: "https://provider.example/cpo.json") }
  let(:vdr_path) { triage_fedramp_vulnerability_detail_report_authorization_boundary_path(boundary) }
  let(:avi_path) { triage_fedramp_accepted_vulnerability_info_authorization_boundary_path(boundary) }

  def user_with(permissions, on: boundary)
    user = create(:user)
    role = create(:role, :authorization_boundary_scoped, permissions: permissions)
    create(:user_role, user: user, role: role, authorization_boundary_id: on.id)
    user
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    scan = create(:scan_run, authorization_boundary: boundary)
    create(:scanner_finding, scan_run: scan, authorization_boundary: boundary, control_id: "CVE-2026-0001",
                             status: "failed", created_at: 2.days.ago)
  end

  it "sends the VDR as a JSON attachment to an evidence.read holder and audits it" do
    sign_in_as(user_with({ "evidence.read" => true }))
    expect {
      get vdr_path, params: { from: 10.days.ago.to_date.iso8601, to: Date.current.iso8601 }
    }.to change { AuditEvent.where(action: "fedramp_vulnerability_detail_report_exported").count }.by(1)

    expect(response).to have_http_status(:ok)
    expect(response.headers["Content-Disposition"]).to include("attachment", "fedramp-vdr.json")
    doc = JSON.parse(response.body)
    expect(doc["vulnerabilities"].map { |v| v["providerTrackingId"] }).to eq([ "CVE-2026-0001" ])
  end

  it "sends the AVI" do
    sign_in_as(create(:user, :admin))
    expect { get avi_path }.to change { AuditEvent.where(action: "fedramp_accepted_vulnerability_info_exported").count }.by(1)
    expect(response.headers["Content-Disposition"]).to include("fedramp-avi.json")
    expect(JSON.parse(response.body)["acceptedVulnerabilities"]).to eq([])
  end

  it "sends the historical activity (#1390), 12 months by default, and audits it" do
    sign_in_as(create(:user, :admin))
    path = triage_fedramp_historical_ver_activity_authorization_boundary_path(boundary)
    expect { get path }.to change { AuditEvent.where(action: "fedramp_historical_ver_activity_exported").count }.by(1)
    expect(response.headers["Content-Disposition"]).to include("fedramp-ver-history.json")
    doc = JSON.parse(response.body)
    expect(doc).to include("activeVulnerabilities", "acceptedVulnerabilities", "generatedAt")
    expect(AuditEvent.where(action: "fedramp_historical_ver_activity_exported").last.metadata["generated_at"])
      .to eq(doc["generatedAt"])
  end

  it "refuses a user without evidence.read on this boundary" do
    sign_in_as(user_with({ "evidence.read" => true }, on: create(:authorization_boundary)))
    get vdr_path
    expect(response).to redirect_to(root_path)
    expect(AuditEvent.where(action: "fedramp_vulnerability_detail_report_exported")).to be_empty
  end

  it "says why when the boundary has no package overview address" do
    boundary.update!(fedramp_package_overview_uri: nil)
    sign_in_as(create(:user, :admin))
    get avi_path
    expect(response).to redirect_to(triage_authorization_boundary_path(boundary))
    expect(flash[:error]).to include("fedramp_package_overview_uri")
  end

  it "never sends a report the validator rejects" do
    invalid = DocumentValidationService::Result.new(
      format: "fedramp", document_type: "x", schema: {}, warnings: [], warnings_total: 0,
      errors: [ { check: "completeness", pointer: "/vulnerabilities/0/detection", message: "required field is blank" } ]
    )
    allow(DocumentValidationService).to receive(:call).and_return(invalid)
    sign_in_as(create(:user, :admin))
    get vdr_path
    expect(response).to redirect_to(triage_authorization_boundary_path(boundary))
    expect(flash[:error]).to include("SPARC produced an invalid report", "/vulnerabilities/0/detection")
  end

  describe "the triage page" do
    it "offers both downloads with a period when the boundary has a package overview address" do
      sign_in_as(create(:user, :admin))
      get triage_authorization_boundary_path(boundary)
      page = Nokogiri::HTML(response.body)
      form = page.at_css("[data-testid='triage-fedramp-reports'] form")
      expect(form["action"]).to eq(vdr_path)
      expect(form["method"]).to eq("get")
      expect(form.at_css("input[name='from'][type='date']")).to be_present
      expect(form.at_css("input[name='to'][type='date']")).to be_present
      expect(form.at_css("[data-testid='triage-download-fedramp-avi']")["formaction"]).to eq(avi_path)
      history = page.at_css("[data-testid='triage-download-fedramp-ver-history']")
      expect(history["href"]).to eq(triage_fedramp_historical_ver_activity_authorization_boundary_path(boundary))
    end

    it "explains why there are no downloads when the boundary has no address" do
      boundary.update!(fedramp_package_overview_uri: nil)
      sign_in_as(create(:user, :admin))
      get triage_authorization_boundary_path(boundary)
      page = Nokogiri::HTML(response.body)
      expect(page.at_css("[data-testid='triage-fedramp-reports-unavailable']")).to be_present
      expect(page.at_css("[data-testid='triage-download-fedramp-vdr']")).to be_nil
      expect(page.at_css("[data-testid='triage-download-fedramp-ver-history']")).to be_nil
    end
  end
end
