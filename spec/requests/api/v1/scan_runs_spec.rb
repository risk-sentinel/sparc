# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::ScanRuns", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin Test") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

  let(:member)         { create(:user) }
  let(:member_token)   { ApiToken.generate!(user: member, name: "Member Test") }
  let(:member_headers) { { "Authorization" => "Bearer #{member_token.plaintext_token}" } }

  let(:boundary) { create(:authorization_boundary) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  # #1354 — a valid HDF v2 document (spec/support/hdf_document_helpers.rb):
  # ingest validates every upload with the hdf CLI.
  def hdf_payload
    hdf_v2_doc([ hdf_v2_control("CVE-1", impact: 0.8, status: "failed"),
                 hdf_v2_control("CVE-2", impact: 0.5, status: "passed") ],
               scanner: "trivy", version: "1.0", platform: "test").to_json
  end

  # Multipart upload — the primary ingest path (a scanner's HDF output file).
  def hdf_upload(content = hdf_payload, name: "scan.hdf.json")
    file = Tempfile.new([ "scan", ".json" ])
    file.write(content)
    file.rewind
    Rack::Test::UploadedFile.new(file.path, "application/json", original_filename: name)
  end

  describe "authentication" do
    it "returns 401 without a token" do
      post api_v1_authorization_boundary_scan_runs_path(boundary)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST .../scan_runs (ingest)" do
    it "ingests an HDF document and returns the run" do
      post api_v1_authorization_boundary_scan_runs_path(boundary),
           params: { file: hdf_upload }, headers: admin_headers

      expect(response).to have_http_status(:created)
      data = JSON.parse(response.body)["data"]
      expect(data["scanner"]).to eq("trivy")
      expect(data["finding_count"]).to eq(2)
      expect(data["failed_count"]).to eq(1)
      expect(data["source_filename"]).to eq("scan.hdf.json")
      expect(boundary.scanner_findings.count).to eq(2)
    end

    it "ingests a raw JSON body (no multipart)" do
      post api_v1_authorization_boundary_scan_runs_path(boundary),
           params: hdf_payload, headers: admin_headers.merge("Content-Type" => "application/json")
      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["data"]["finding_count"]).to eq(2)
    end

    it "returns 422 on malformed HDF content" do
      post api_v1_authorization_boundary_scan_runs_path(boundary),
           params: { file: hdf_upload("{ not json") }, headers: admin_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to match(/Invalid HDF JSON/)
    end

    it "returns 422 when the JSON carries no controls" do
      post api_v1_authorization_boundary_scan_runs_path(boundary),
           params: { file: hdf_upload('{"baselines":[]}') }, headers: admin_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to match(/No HDF controls/)
    end

    # #1354 — the hdf CLI validates every upload before SPARC reads it.
    it "returns 422 with hdf's reason when the JSON is not HDF" do
      post api_v1_authorization_boundary_scan_runs_path(boundary),
           params: { file: hdf_upload("{}") }, headers: admin_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to match(/HDF validation failed: .*baselines is required/)
      expect(boundary.scan_runs).to be_empty
    end

    it "ingests an HDF v3 document" do
      v3 = Rails.root.join("spec/fixtures/files/hdf/sample-results.v3.hdf.json").read
      post api_v1_authorization_boundary_scan_runs_path(boundary),
           params: { file: hdf_upload(v3) }, headers: admin_headers
      expect(response).to have_http_status(:created)
      data = JSON.parse(response.body)["data"]
      expect(data.slice("scanner", "finding_count", "failed_count"))
        .to eq("scanner" => "sparc-sample-profile", "finding_count" => 1, "failed_count" => 1)
    end

    it "forbids a member without evidence.write" do
      post api_v1_authorization_boundary_scan_runs_path(boundary),
           params: { file: hdf_upload }, headers: member_headers
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET .../scan_runs" do
    it "lists runs newest-first for admin" do
      create(:scan_run, authorization_boundary: boundary, scanner: "trivy")
      create(:scan_run, authorization_boundary: boundary, scanner: "gitleaks")

      get api_v1_authorization_boundary_scan_runs_path(boundary), headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"].length).to eq(2)
    end
  end

  describe "GET .../scan_runs/:id" do
    it "shows a run by uuid" do
      run = create(:scan_run, authorization_boundary: boundary)
      get api_v1_authorization_boundary_scan_run_path(boundary, run.uuid), headers: admin_headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["uuid"]).to eq(run.uuid)
    end
  end
end
