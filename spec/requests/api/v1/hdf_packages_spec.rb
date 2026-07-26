# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::HdfPackages", type: :request do
  let(:admin)         { create(:user, :admin) }
  let(:admin_token)   { ApiToken.generate!(user: admin, name: "Admin Test") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

  let(:member)         { create(:user) }
  let(:member_token)   { ApiToken.generate!(user: member, name: "Member Test") }
  let(:member_headers) { { "Authorization" => "Bearer #{member_token.plaintext_token}" } }

  let(:boundary) { create(:authorization_boundary) }
  let(:run)      { create(:scan_run, authorization_boundary: boundary) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    create(:scanner_finding, :failed, scan_run: run, authorization_boundary: boundary, control_id: "CVE-1")
  end

  def path = api_v1_authorization_boundary_hdf_package_path(boundary)

  it "returns the signed package for an admin" do
    get path, headers: admin_headers
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["signature"]).to be_present
    expect(body["payload"]["boundary"]["slug"]).to eq(boundary.slug)
    expect(body["payload"]["findings"].first["control_id"]).to eq("CVE-1")
  end

  it "forbids a member without evidence.read" do
    get path, headers: member_headers
    expect(response).to have_http_status(:forbidden)
  end

  it "401 without a token" do
    get path
    expect(response).to have_http_status(:unauthorized)
  end
end
