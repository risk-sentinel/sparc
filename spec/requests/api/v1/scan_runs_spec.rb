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

  def hdf_payload
    {
      "platform" => { "name" => "test" },
      "profiles" => [ {
        "name" => "trivy", "version" => "1.0",
        "controls" => [
          { "id" => "CVE-1", "title" => "t", "desc" => "d", "impact" => 0.8, "results" => [ { "status" => "failed" } ] },
          { "id" => "CVE-2", "title" => "t", "desc" => "d", "impact" => 0.5, "results" => [ { "status" => "passed" } ] }
        ]
      } ]
    }.to_json
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
           params: { file: hdf_upload("{}") }, headers: admin_headers
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to match(/No HDF controls/)
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
