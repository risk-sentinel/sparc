# frozen_string_literal: true

require "rails_helper"

# #1390 — the Ongoing reports tab of the boundary's FedRAMP page, and its API.
RSpec.describe "Boundary FedRAMP ongoing certification reports", type: :request do
  let(:boundary) do
    create(:authorization_boundary, :fedramp, fedramp_package_overview_uri: "https://trust.example/cpo.json",
                                              fedramp_active_agencies: [ "Example Agency" ])
  end
  let(:page_path) { fedramp_ongoing_reports_authorization_boundary_path(boundary) }
  let(:api_path) { "/api/v1/authorization_boundaries/#{boundary.id}/fedramp_ongoing_reports" }

  def user_with(permissions, on: boundary)
    user = create(:user)
    role = create(:role, :authorization_boundary_scoped, permissions: permissions)
    create(:user_role, user: user, role: role, authorization_boundary_id: on.id)
    user
  end

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: SecureRandom.hex(4)).plaintext_token}" }
  end

  def html = Nokogiri::HTML(response.body)

  let(:issuer) { user_with({ "evidence.read" => true, "evidence.write" => true, "incident.read" => true }) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  it "shows the report for the period, downloads it, issues it from the button as rendered, and lists it" do
    sign_in_as(issuer)
    get page_path, params: { recommendations: "Rotate keys" }
    expect(html.at_css("[data-testid='fedramp-ocr-draft'] [data-testid='fedramp-ocr-document']").text)
      .to include("Rotate keys", "Example Agency", "None occurred in the period")

    get html.at_css("[data-testid='fedramp-ocr-download-draft']")["href"]
    expect(response.headers["Content-Disposition"]).to include("attachment")
    expect(JSON.parse(response.body)["updatedRecommendations"]).to eq([ "Rotate keys" ])

    get page_path, params: { recommendations: "Rotate keys" }
    form = html.at_css("[data-testid='fedramp-ocr-issue-form']")
    fields = form.css("input[type='hidden']").to_h { |i| [ i["name"], i["value"] ] }.except("authenticity_token")
    expect {
      post form["action"], params: fields
    }.to change { AuditEvent.where(action: "fedramp_ongoing_report_issued").count }.by(1)
    report = boundary.fedramp_ongoing_reports.sole
    expect(response).to redirect_to(fedramp_ongoing_report_authorization_boundary_path(boundary, report))
    expect(report.recommendations).to eq([ "Rotate keys" ])

    get fedramp_ongoing_report_authorization_boundary_path(boundary, report)
    expect(html.at_css("[data-testid='fedramp-ocr-report']").text).to include(report.sha256)
    get document_fedramp_ongoing_report_authorization_boundary_path(boundary, report)
    expect(JSON.parse(response.body)).to eq(report.document)

    get page_path
    expect(html.css("[data-testid='fedramp-ocr-issued-row']").size).to eq(1)
    expect(html.at_css("[data-testid='fedramp-ocr-next']").text).to include((report.period_to + 3.months).to_s)
  end

  it "needs incident.read too, because the report summarizes incidents; the tab shows only with it" do
    sign_in_as(user_with({ "evidence.read" => true, "evidence.write" => true }))
    get page_path
    expect(response).to redirect_to(root_path)
    get fedramp_significant_changes_authorization_boundary_path(boundary)
    expect(Nokogiri::HTML(response.body).at_css("[data-testid='fedramp-tab-ongoing']")).to be_nil

    sign_in_as(user_with({ "evidence.read" => true, "incident.read" => true }))
    get page_path
    expect(html.at_css("[data-testid='fedramp-ocr-issue']")).to be_nil
    post page_path, params: { recommendations: "x" }
    expect(boundary.fedramp_ongoing_reports).to be_empty
  end

  it "says why a period is refused" do
    sign_in_as(issuer)
    get page_path, params: { to: "2999-01-01" }
    expect(html.at_css("[data-testid='fedramp-ocr-error']").text).to include("future")
  end

  it "takes the agencies using the service from the boundary's edit form as rendered, and from the API" do
    admin = create(:user, :admin)
    sign_in_as(admin)
    get edit_authorization_boundary_path(boundary)
    field = html.at_css("[data-testid='boundary-fedramp-active-agencies']")
    expect(field["name"]).to eq("authorization_boundary[fedramp_active_agencies]")
    expect(field.text.strip).to eq("Example Agency")
    patch authorization_boundary_path(boundary),
          params: { authorization_boundary: { field["name"][/\[(\w+)\]\z/, 1] => "Agency A\n\nAgency B\nAgency A" } }
    expect(boundary.reload.fedramp_active_agencies).to eq([ "Agency A", "Agency B" ])

    patch "/api/v1/authorization_boundaries/#{boundary.id}",
          params: { authorization_boundary: { fedramp_active_agencies: [ "Agency C" ] } }, headers: headers_for(admin), as: :json
    expect(response.parsed_body.dig("data", "fedramp_active_agencies")).to eq([ "Agency C" ])
  end

  describe "API" do
    it "returns the draft, issues a report (201), lists it and shows it with its document" do
      headers = headers_for(issuer)
      get "#{api_path}/draft", params: { recommendations: [ "Rotate keys" ] }, headers: headers
      expect(response.parsed_body).to include("updatedRecommendations" => [ "Rotate keys" ], "activeAgencies" => [ "Example Agency" ])

      post api_path, params: { fedramp_ongoing_report: { recommendations: [ "Rotate keys" ] } }, headers: headers, as: :json
      expect(response).to have_http_status(:created)
      uuid = response.parsed_body.dig("data", "uuid")

      get api_path, headers: headers
      expect(response.parsed_body["data"].sole).to include("uuid" => uuid)
      expect(response.parsed_body["data"].sole).not_to have_key("document")
      expect(response.parsed_body["meta"]["next_target_date"]).to be_present

      get "#{api_path}/#{uuid}", headers: headers
      expect(response.parsed_body.dig("data", "document", "updatedRecommendations")).to eq([ "Rotate keys" ])

      post api_path, params: { fedramp_ongoing_report: {} }, headers: headers, as: :json
      expect(response).to have_http_status(:unprocessable_content) # overlaps the one issued
    end

    it "403s without incident.read and 422s while FedRAMP is off" do
      get api_path, headers: headers_for(user_with({ "evidence.read" => true }))
      expect(response).to have_http_status(:forbidden)
      boundary.update!(fedramp_enabled: false)
      get api_path, headers: headers_for(issuer)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end
end
