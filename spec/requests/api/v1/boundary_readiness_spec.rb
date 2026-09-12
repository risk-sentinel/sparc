# frozen_string_literal: true

require "rails_helper"

# #940 S1 — the completeness report over the API. The UI card (S2) is a thin
# client over this same endpoint, so the contract is pinned here.
RSpec.describe "GET /api/v1/authorization_boundaries/:id/readiness", type: :request do
  let(:boundary) { create(:authorization_boundary) }
  let(:user) { create(:user, admin: true) }
  let(:headers) do
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'readiness').plaintext_token}" }
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  it "returns the report" do
    get "/api/v1/authorization_boundaries/#{boundary.id}/readiness", headers: headers

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("data", "boundary", "name")).to eq(boundary.name)
  end

  it "carries every section with a state, a detail and a guide anchor" do
    get "/api/v1/authorization_boundaries/#{boundary.id}/readiness", headers: headers

    sections = response.parsed_body.dig("data", "sections")
    expect(sections).to be_present
    expect(sections.map { |s| s["status"] }).to all(be_in(%w[complete partial absent not_modelled]))
    expect(sections.map { |s| s["guide_anchor"] }).to all(be_present)
  end

  it "summarises by state" do
    get "/api/v1/authorization_boundaries/#{boundary.id}/readiness", headers: headers

    summary = response.parsed_body.dig("data", "summary")
    expect(summary.keys).to match_array(%w[complete partial absent not_modelled])
  end

  # Environments are reported from the boundary's sub-boundaries, each of which
  # carries an `environment`. A boundary with none has not said where it runs.
  it "reports environments as absent when the boundary has no sub-boundaries" do
    get "/api/v1/authorization_boundaries/#{boundary.id}/readiness", headers: headers

    environments = response.parsed_body.dig("data", "sections").find { |s| s["key"] == "environments" }
    expect(environments["status"]).to eq("absent")
  end

  it "reports environments as complete once one is recorded" do
    create(:boundary, authorization_boundary: boundary, name: "Prod", environment: "production")

    get "/api/v1/authorization_boundaries/#{boundary.id}/readiness", headers: headers

    environments = response.parsed_body.dig("data", "sections").find { |s| s["key"] == "environments" }
    expect(environments["status"]).to eq("complete")
    expect(environments["detail"]).to include("production")
  end

  it "resolves a boundary by slug as well as id" do
    get "/api/v1/authorization_boundaries/#{boundary.slug}/readiness", headers: headers

    expect(response).to have_http_status(:ok)
  end

  it "refuses an unauthenticated caller" do
    get "/api/v1/authorization_boundaries/#{boundary.id}/readiness"

    expect(response).to have_http_status(:unauthorized)
  end

  # Safe to poll from a pipeline and to render on every page load.
  it "is read-only" do
    # `boundary` is a lazy let — reference it BEFORE capturing counts, or the
    # request creates it and the comparison measures the fixture rather than
    # the endpoint.
    boundary
    before_counts = [ AuthorizationBoundary.count, SspDocument.count ]

    get "/api/v1/authorization_boundaries/#{boundary.id}/readiness", headers: headers

    expect([ AuthorizationBoundary.count, SspDocument.count ]).to eq(before_counts)
  end
end
