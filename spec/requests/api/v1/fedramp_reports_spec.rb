# frozen_string_literal: true

require "rails_helper"

# #1354 / #1384 / #1390 — GET /api/v1/authorization_boundaries/:id/fedramp/
# vulnerability_detail_report, .../accepted_vulnerability_info and
# .../historical_ver_activity, and .../certification_package_overview (#1390).
# evidence.read on the boundary; each download audited; 422 without the
# boundary's package overview address; 502, never the document, when SPARC's
# own report fails validation.
RSpec.describe "API v1 FedRAMP reports", type: :request do
  let(:boundary) { create(:authorization_boundary, fedramp_package_overview_uri: "https://provider.example/cpo.json") }
  let(:base) { "/api/v1/authorization_boundaries/#{boundary.id}/fedramp" }
  let(:vdr_path) { "#{base}/vulnerability_detail_report" }
  let(:avi_path) { "#{base}/accepted_vulnerability_info" }

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: SecureRandom.hex(4)).plaintext_token}" }
  end

  def user_with(permissions, on: boundary)
    user = create(:user)
    role = create(:role, :authorization_boundary_scoped, permissions: permissions)
    create(:user_role, user: user, role: role, authorization_boundary_id: on.id)
    user
  end

  let(:reader) { user_with({ "evidence.read" => true }) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    scan = create(:scan_run, authorization_boundary: boundary)
    create(:scanner_finding, scan_run: scan, authorization_boundary: boundary, control_id: "CVE-2026-0001",
                             status: "failed", created_at: 3.days.ago)
    create(:scanner_finding, scan_run: scan, authorization_boundary: boundary, control_id: "CVE-2026-0002",
                             status: "failed", created_at: 3.days.ago)
    create(:finding_disposition, :waiver, authorization_boundary: boundary, control_id: "CVE-2026-0002",
                                          approval_status: "approved", approved_at: 1.day.ago, reason: "AO waiver.")
  end

  # [report, audit action, vulnerabilities it lists here, carries a reportPeriod]
  [ [ "vulnerability_detail_report", "fedramp_vulnerability_detail_report_exported", 1, true ],
    [ "accepted_vulnerability_info", "fedramp_accepted_vulnerability_info_exported", 1, true ],
    [ "historical_ver_activity", "fedramp_historical_ver_activity_exported", 2, false ] ].each do |report, action, count, period|
    describe report do
      let(:path) { "#{base}/#{report}" }

      it "401s without a token" do
        get path
        expect(response).to have_http_status(:unauthorized)
      end

      it "403s with evidence.read on another boundary only" do
        get path, headers: headers_for(user_with({ "evidence.read" => true }, on: create(:authorization_boundary)))
        expect(response).to have_http_status(:forbidden)
      end

      it "403s with a permission other than evidence.read on this boundary" do
        get path, headers: headers_for(user_with({ "ssp.read" => true }))
        expect(response).to have_http_status(:forbidden)
      end

      it "serves the report to an evidence.read holder and audits the download" do
        expect {
          get path, params: { from: "2026-01-01T00:00:00Z", to: Time.current.utc.iso8601 }, headers: headers_for(reader)
        }.to change { AuditEvent.where(action: action).count }.by(1)

        expect(response).to have_http_status(:ok)
        event = AuditEvent.where(action: action).last
        expect(event.user).to eq(reader)
        expect(event.metadata).to include("authorization_boundary_id" => boundary.id, "vulnerabilities" => count)
        if period
          expect(event.metadata).to include("from" => "2026-01-01T00:00:00Z")
        else
          expect(event.metadata["generated_at"]).to eq(response.parsed_body["generatedAt"])
        end
      end

      it "serves an instance administrator, by slug" do
        get "/api/v1/authorization_boundaries/#{boundary.slug}/fedramp/#{report}", headers: headers_for(create(:user, :admin))
        expect(response).to have_http_status(:ok)
      end

      it "422s, naming the boundary setting, when the boundary has no package overview address" do
        boundary.update!(fedramp_package_overview_uri: nil)
        get path, headers: headers_for(reader)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to include("fedramp_package_overview_uri")
      end

      it "422s on a period it cannot read" do
        get path, params: { from: "last week" }, headers: headers_for(reader)
        expect(response).to have_http_status(:unprocessable_content)
        expect(response.parsed_body["error"]).to include("ISO 8601")
      end

      it "502s with the errors, and never the document, when SPARC's report fails validation" do
        invalid = DocumentValidationService::Result.new(
          format: "fedramp", document_type: "x", schema: {}, warnings: [], warnings_total: 0,
          errors: [ { check: "schema", pointer: "/reportPeriod", message: "is bad" } ]
        )
        allow(DocumentValidationService).to receive(:call).and_return(invalid)

        expect { get path, headers: headers_for(reader) }.not_to(change { AuditEvent.where(action: action).count })
        expect(response).to have_http_status(:bad_gateway)
        body = response.parsed_body
        expect(body["error"]).to eq("SPARC produced an invalid report")
        expect(body["details"]).to eq([ { "check" => "schema", "pointer" => "/reportPeriod", "message" => "is bad" } ])
        expect(body).not_to have_key("certificationPackageOverviewUri")
      end
    end
  end

  it "lists the accepted vulnerability only in the AVI" do
    get vdr_path, headers: headers_for(reader)
    expect(response.parsed_body["vulnerabilities"].map { |v| v["providerTrackingId"] }).to eq([ "CVE-2026-0001" ])
    expect(response.parsed_body["$schema"]).to end_with("fedramp-vulnerability-detail-report-schema-2026-06-24.json")

    get avi_path, headers: headers_for(reader)
    entry = response.parsed_body["acceptedVulnerabilities"].sole
    expect(entry).to include("acceptanceRationale" => "AO waiver.")
    expect(entry.dig("vulnerabilityDetail", "providerTrackingId")).to eq("CVE-2026-0002")
  end

  it "lists both in the historical activity, active and accepted apart" do
    get "#{base}/historical_ver_activity", headers: headers_for(reader)
    body = response.parsed_body
    expect(body["$schema"]).to end_with("fedramp-historical-ver-activity-schema-2026-06-24.json")
    expect(body["activeVulnerabilities"].map { |v| v["providerTrackingId"] }).to eq([ "CVE-2026-0001" ])
    expect(body["acceptedVulnerabilities"].sole.dig("vulnerabilityDetail", "providerTrackingId")).to eq("CVE-2026-0002")
    expect(body).not_to have_key("reportPeriod")
  end

  # #1390 — FRC-CSO-PKG, written from the boundary's FedRAMP fields.
  describe "certification_package_overview" do
    let(:path) { "#{base}/certification_package_overview" }
    let(:action) { "fedramp_certification_package_overview_exported" }

    before { boundary.update!(attributes_for(:authorization_boundary, :fedramp_overview_ready).slice(:fedramp_package, :fedramp_contacts)) }

    it "401s without a token and 403s without evidence.read on this boundary" do
      get path
      expect(response).to have_http_status(:unauthorized)
      get path, headers: headers_for(user_with({ "ssp.read" => true }))
      expect(response).to have_http_status(:forbidden)
    end

    it "serves the overview to an evidence.read holder and audits the download" do
      expect { get path, headers: headers_for(reader) }.to change { AuditEvent.where(action: action).count }.by(1)
      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["$schema"]).to end_with("fedramp-certification-package-overview-schema-2026-06-24.json")
      expect(body.dig("serviceIdentification", "serviceName")).to eq("Example Cloud")
      expect(AuditEvent.where(action: action).last.metadata).to include("authorization_boundary_id" => boundary.id, "contacts" => 2)
    end

    it "is served by the boundary UUID, the form SPARC's own overview address uses" do
      get "/api/v1/authorization_boundaries/#{boundary.uuid}/fedramp/certification_package_overview", headers: headers_for(reader)
      expect(response).to have_http_status(:ok)
    end

    it "needs no overview address" do
      boundary.update!(fedramp_package_overview_uri: nil)
      get path, headers: headers_for(reader)
      expect(response).to have_http_status(:ok)
    end

    it "422s, listing what is missing, when the boundary lacks a required field" do
      boundary.update!(fedramp_package: { website: "" })
      expect { get path, headers: headers_for(reader) }.not_to(change { AuditEvent.where(action: action).count })
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("Missing: Website")
    end

    it "502s, never the document, when SPARC's overview fails validation" do
      invalid = DocumentValidationService::Result.new(
        format: "fedramp", document_type: "x", schema: {}, warnings: [], warnings_total: 0,
        errors: [ { check: "schema", pointer: "/serviceIdentification", message: "is bad" } ]
      )
      allow(DocumentValidationService).to receive(:call).and_return(invalid)
      get path, headers: headers_for(reader)
      expect(response).to have_http_status(:bad_gateway)
      expect(response.parsed_body).to include("document_type" => "certification-package-overview")
      expect(response.parsed_body).not_to have_key("serviceIdentification")
    end
  end

  describe "SPARC's own overview address (#1390)" do
    around do |example|
      saved = ENV.fetch("SPARC_APP_URL", nil)
      ENV["SPARC_APP_URL"] = "https://sparc.example.gov"
      example.run
    ensure
      saved.nil? ? ENV.delete("SPARC_APP_URL") : ENV["SPARC_APP_URL"] = saved
    end

    it "is the address the reports name when the boundary chooses it" do
      boundary.update!(fedramp_overview_from_sparc: true)
      get vdr_path, headers: headers_for(reader)
      expect(response.parsed_body["certificationPackageOverviewUri"]).to eq(
        "https://sparc.example.gov/api/v1/authorization_boundaries/#{boundary.uuid}/fedramp/certification_package_overview"
      )
    end

    it "422s, saying why, once SPARC_APP_URL is no longer https" do
      boundary.update!(fedramp_overview_from_sparc: true)
      ENV["SPARC_APP_URL"] = "http://sparc.example.gov"
      get vdr_path, headers: headers_for(reader)
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to include("SPARC_APP_URL is not an https:// address")
    end
  end
end
