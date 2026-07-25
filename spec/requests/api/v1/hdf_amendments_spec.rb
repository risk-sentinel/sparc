# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::HdfAmendments", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin Test") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

  let(:member)         { create(:user) }
  let(:member_token)   { ApiToken.generate!(user: member, name: "Member Test") }
  let(:member_headers) { { "Authorization" => "Bearer #{member_token.plaintext_token}" } }

  let(:boundary) { create(:authorization_boundary) }
  let(:scan_run) { create(:scan_run, authorization_boundary: boundary) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    # Stub only the binary call; the real export service builds from DB records.
    allow_any_instance_of(HdfRunner).to receive(:amend_verify).and_return(true)

    create(:scanner_finding, :failed, scan_run: scan_run, authorization_boundary: boundary,
           control_id: "CVE-1", severity: "HIGH")
    create(:finding_disposition, authorization_boundary: boundary, control_id: "CVE-1",
           kind: "poam", reason: "tracked")
  end

  def path
    api_v1_authorization_boundary_hdf_amendments_path(boundary)
  end

  it "returns 401 without a token" do
    get path
    expect(response).to have_http_status(:unauthorized)
  end

  it "exports the Amendments artefact for the boundary" do
    get path, headers: admin_headers
    expect(response).to have_http_status(:ok)
    doc = JSON.parse(response.body)
    expect(doc["overrides"].length).to eq(1)
    expect(doc["overrides"].first["requirementId"]).to eq("CVE-1")
    expect(doc["overrides"].first["type"]).to eq("poam")
    expect(doc["amendmentId"]).to be_present
  end

  it "accepts verify=false" do
    get path, params: { verify: "false" }, headers: admin_headers
    expect(response).to have_http_status(:ok)
  end

  it "returns 422 when hdf amend verify fails" do
    allow_any_instance_of(HdfRunner).to receive(:amend_verify).and_raise(
      HdfRunner::Error.new("schema mismatch", command: "hdf amend verify", exit_code: 1, stderr: "bad")
    )
    get path, headers: admin_headers
    expect(response).to have_http_status(:unprocessable_entity)
    expect(JSON.parse(response.body)["error"]).to match(/verification failed/i)
  end

  it "forbids a member without evidence.read" do
    get path, headers: member_headers
    expect(response).to have_http_status(:forbidden)
  end
end
