# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::ScannerFindings", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin Test") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

  let(:member)         { create(:user) }
  let(:member_token)   { ApiToken.generate!(user: member, name: "Member Test") }
  let(:member_headers) { { "Authorization" => "Bearer #{member_token.plaintext_token}" } }

  let(:boundary) { create(:authorization_boundary) }
  let(:scan_run) { create(:scan_run, authorization_boundary: boundary) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  describe "GET .../scanner_findings" do
    before do
      create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary,
             control_id: "CVE-A", severity: "HIGH")
      create(:scanner_finding, :passed, scan_run: scan_run, authorization_boundary: boundary,
             control_id: "CVE-B", severity: "LOW")
    end

    it "lists findings for the boundary" do
      get api_v1_authorization_boundary_scanner_findings_path(boundary), headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"].length).to eq(2)
    end

    it "filters by status" do
      get api_v1_authorization_boundary_scanner_findings_path(boundary),
          params: { status: "failed" }, headers: admin_headers
      data = JSON.parse(response.body)["data"]
      expect(data.map { |f| f["control_id"] }).to contain_exactly("CVE-A")
    end

    it "filters by severity (case-insensitive)" do
      get api_v1_authorization_boundary_scanner_findings_path(boundary),
          params: { severity: "high" }, headers: admin_headers
      expect(JSON.parse(response.body)["data"].map { |f| f["control_id"] }).to contain_exactly("CVE-A")
    end

    it "forbids a member without evidence.read" do
      get api_v1_authorization_boundary_scanner_findings_path(boundary), headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /scanner_findings/:id" do
    it "shows a finding by uuid with its disposition kind" do
      finding = create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary,
                       control_id: "CVE-X")
      create(:finding_disposition, authorization_boundary: boundary, control_id: "CVE-X", kind: "poam")

      get api_v1_scanner_finding_path(finding.uuid), headers: admin_headers
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["control_id"]).to eq("CVE-X")
      expect(data["disposition_kind"]).to eq("poam")
      expect(data["raw_hdf"]).to be_present
    end
  end
end
