# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::AuthorizationBoundaries", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:api_token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  describe "GET /api/v1/authorization_boundaries" do
    it "returns list of boundaries for admin" do
      create_list(:authorization_boundary, 3)

      get api_v1_authorization_boundaries_path, headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]).to be_an(Array)
      expect(parsed["data"].length).to be >= 3
      expect(parsed["meta"]).to include("page", "count")
    end
  end

  describe "GET /api/v1/authorization_boundaries/:id" do
    it "returns boundary details" do
      boundary = create(:authorization_boundary)

      get api_v1_authorization_boundary_path(boundary.slug), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["slug"]).to eq(boundary.slug)
      expect(parsed["data"]["name"]).to eq(boundary.name)
    end
  end

  describe "POST /api/v1/authorization_boundaries" do
    it "creates a boundary" do
      boundary_params = {
        authorization_boundary: {
          name: "Test Boundary",
          description: "A test authorization boundary",
          status: "draft"
        }
      }

      expect {
        post api_v1_authorization_boundaries_path, params: boundary_params, headers: auth_headers, as: :json
      }.to change(AuthorizationBoundary, :count).by(1)

      expect(response).to have_http_status(:created)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["name"]).to eq("Test Boundary")
    end
  end

  describe "PATCH /api/v1/authorization_boundaries/:id" do
    it "updates a boundary" do
      boundary = create(:authorization_boundary)

      patch api_v1_authorization_boundary_path(boundary.slug),
            params: { authorization_boundary: { description: "Updated description" } },
            headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["description"]).to eq("Updated description")
    end
  end

  describe "DELETE /api/v1/authorization_boundaries/:id" do
    it "deletes a boundary" do
      boundary = create(:authorization_boundary)

      expect {
        delete api_v1_authorization_boundary_path(boundary.slug), headers: auth_headers
      }.to change(AuthorizationBoundary, :count).by(-1)

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["deleted"]).to be true
    end
  end

  context "non-admin user" do
    let(:regular_user) { create(:user) }
    let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
    let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

    it "sees only own boundaries in index" do
      # Create boundaries the user does NOT have access to
      create_list(:authorization_boundary, 2)

      get api_v1_authorization_boundaries_path, headers: user_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      # Non-admin sees only boundaries they have roles on (none in this case)
      expect(parsed["data"]).to be_an(Array)
      expect(parsed["data"].length).to eq(0)
    end
  end

  # #629 — admin-only bulk delete; partial-success result.
  describe "DELETE /api/v1/authorization_boundaries/bulk" do
    it "deletes unassociated boundaries and reports blocked ones (admin)" do
      deletable = create(:authorization_boundary)
      blocked   = create(:authorization_boundary)
      create(:ssp_document, authorization_boundary: blocked)

      delete bulk_api_v1_authorization_boundaries_path,
        params: { ids: [ deletable.id, blocked.id ] }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["deleted"].map { |d| d["id"] }).to eq([ deletable.id ])
      expect(data["blocked"].map { |b| b["id"] }).to eq([ blocked.id ])
      expect(AuthorizationBoundary.exists?(deletable.id)).to be(false)
      expect(AuthorizationBoundary.exists?(blocked.id)).to be(true)
    end

    # #1018 — a misspelled key used to answer 200 with zeros, telling the caller
    # the records were not there rather than that the request was malformed.
    it "refuses a body with no `ids`, and deletes nothing" do
      boundary = create(:authorization_boundary)

      delete bulk_api_v1_authorization_boundaries_path,
        params: { boundary_ids: [ boundary.id ] }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["details"].join).to match(/`ids` is required/)
      expect(response.parsed_body["expected"]).to eq("ids" => [ "string-or-integer" ])
      expect(AuthorizationBoundary.exists?(boundary.id)).to be(true)
    end

    it "refuses an `ids` that is not an array, naming what it received" do
      delete bulk_api_v1_authorization_boundaries_path,
        params: { ids: "1,2,3" }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["details"].join).to match(/must be an ARRAY/)
    end

    # The distinction the endpoint could not previously express: an empty list
    # genuinely IS nothing to do, and must stay a success.
    it "still succeeds for an empty `ids` array" do
      delete bulk_api_v1_authorization_boundaries_path,
        params: { ids: [] }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.dig("meta", "deleted")).to eq(0)
    end

    it "returns 403 for a non-admin" do
      regular_user = create(:user)
      user_token = ApiToken.generate!(user: regular_user, name: "User Token")
      boundary = create(:authorization_boundary)

      delete bulk_api_v1_authorization_boundaries_path,
        params: { ids: [ boundary.id ] },
        headers: { "Authorization" => "Bearer #{user_token.plaintext_token}" }, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(AuthorizationBoundary.exists?(boundary.id)).to be(true)
    end
  end
end
