# frozen_string_literal: true

require "rails_helper"

# #1354 — GET /api/v1/authorization_boundaries/:id/exchange_index: what the
# boundary serves back out. Read with evidence.read on the boundary; every
# read is audited (FedRAMP CDS-TRC-ACL / CDS-TRC-AAI).
RSpec.describe "API v1 exchange index", type: :request do
  let(:boundary) { create(:authorization_boundary) }
  let(:path) { "/api/v1/authorization_boundaries/#{boundary.id}/exchange_index" }

  def headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: SecureRandom.hex(4)).plaintext_token}" }
  end

  def user_with(permissions, on: boundary)
    user = create(:user)
    role = create(:role, :authorization_boundary_scoped, permissions: permissions)
    create(:user_role, user: user, role: role, authorization_boundary_id: on.id)
    user
  end

  let(:vdr) do
    { "certificationPackageOverviewUri" => "https://provider.example/package/cpo.json",
      "reportPeriod" => { "from" => "2026-10-01T00:00:00Z", "to" => "2026-10-31T23:59:59Z" },
      "vulnerabilities" => [] }.to_json
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  it "401s without a token" do
    get path
    expect(response).to have_http_status(:unauthorized)
  end

  it "403s without evidence.read on this boundary" do
    get path, headers: headers_for(user_with({ "evidence.read" => true }, on: create(:authorization_boundary)))
    expect(response).to have_http_status(:forbidden)
  end

  it "lists the boundary's documents, accepted received versions only, and audits who read it" do
    reader = user_with({ "evidence.read" => true })
    accepted = ReceivedDocumentService.call(boundary: boundary, bytes: vdr, source: "upload", filename: "vdr.json").document
    ReceivedDocumentReviewService.accept(accepted, user: create(:user, :admin))
    pending = ReceivedDocumentService.call(boundary: boundary, bytes: vdr.sub("23:59:59", "23:00:00"), source: "upload").document

    expect {
      get path, headers: headers_for(reader)
    }.to change { AuditEvent.where(action: "exchange_index_served").count }.by(1)

    expect(response).to have_http_status(:ok)
    data = response.parsed_body["data"]
    expect(data.dig("authorization_boundary", "id")).to eq(boundary.id)
    received = data["documents"].select { |d| d["origin"] == "received" }
    expect(received.map { |d| d["id"] }).to eq([ accepted.id ])
    expect(received.first).to include("sha256" => accepted.sha256,
                                      "download_url" => "/api/v1/authorization_boundaries/#{boundary.id}/received_documents/#{accepted.id}/file")
    expect(received.map { |d| d["id"] }).not_to include(pending.id)
    expect(data["documents"]).to include(a_hash_including("origin" => "sparc", "format" => "hdf", "document_type" => "system"))

    event = AuditEvent.where(action: "exchange_index_served").last
    expect(event.user).to eq(reader)
    expect(event.metadata).to include("authorization_boundary_id" => boundary.id, "received" => 1)
  end

  # #1354 / #1384 — the FedRAMP reports, only once they can be built.
  it "lists the FedRAMP VDR and AVI only when the boundary has a package overview address" do
    admin = create(:user, :admin)
    get path, headers: headers_for(admin)
    expect(response.parsed_body.dig("data", "documents").map { |d| d["format"] }).not_to include("fedramp")

    boundary.update!(fedramp_package_overview_uri: "https://provider.example/package/cpo.json")
    get path, headers: headers_for(admin)
    fedramp = response.parsed_body.dig("data", "documents").select { |d| d["format"] == "fedramp" }
    expect(fedramp).to contain_exactly(
      a_hash_including("origin" => "sparc", "document_type" => "vulnerability-detail-report", "sha256" => nil,
                       "download_url" => "/api/v1/authorization_boundaries/#{boundary.id}/fedramp/vulnerability_detail_report"),
      a_hash_including("origin" => "sparc", "document_type" => "accepted-vulnerability-info", "sha256" => nil,
                       "download_url" => "/api/v1/authorization_boundaries/#{boundary.id}/fedramp/accepted_vulnerability_info"),
      a_hash_including("origin" => "sparc", "document_type" => "historical-ver-activity", "sha256" => nil,
                       "download_url" => "/api/v1/authorization_boundaries/#{boundary.id}/fedramp/historical_ver_activity")
    )
    fedramp.each do |entry|
      get entry["download_url"], headers: headers_for(admin)
      expect(response).to have_http_status(:ok)
    end
  end

  it "takes the boundary's slug" do
    get "/api/v1/authorization_boundaries/#{boundary.slug}/exchange_index", headers: headers_for(create(:user, :admin))
    expect(response).to have_http_status(:ok)
  end
end
