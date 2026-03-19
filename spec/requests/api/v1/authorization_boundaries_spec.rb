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
end
