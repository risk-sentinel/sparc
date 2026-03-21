# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Discovery", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:admin_token) { ApiToken.generate!(user: admin, name: "Admin Token") }
  let(:admin_headers) { { "Authorization" => "Bearer #{admin_token.plaintext_token}" } }

  let(:boundary) { create(:authorization_boundary) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  describe "authentication" do
    it "returns 401 without a token" do
      get "/api/v1/available"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/available" do
    it "returns correct response structure" do
      get "/api/v1/available", headers: admin_headers

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)

      expect(parsed["api_version"]).to eq("v1")
      expect(parsed["system_id"]).to eq("sparc-application")
      expect(parsed["authenticated_as"]).to be_present
      expect(parsed["auth_mode"]).to be_present
      expect(parsed["endpoints"]).to be_an(Array)
    end

    context "as admin" do
      it "sees all endpoints" do
        get "/api/v1/available", headers: admin_headers
        parsed = JSON.parse(response.body)
        endpoints = parsed["endpoints"]

        # Admin should see every registered endpoint
        registry_count = Api::V1::DiscoveryController::ENDPOINT_REGISTRY.length
        expect(endpoints.length).to eq(registry_count)
      end

      it "sees all HTTP methods including POST, PUT, DELETE" do
        get "/api/v1/available", headers: admin_headers
        parsed = JSON.parse(response.body)
        endpoints = parsed["endpoints"]

        ssp_collection = endpoints.find { |e| e["path"] == "/api/v1/ssp_documents" }
        expect(ssp_collection["methods"]).to include("GET", "POST")

        ssp_member = endpoints.find { |e| e["path"] == "/api/v1/ssp_documents/:slug" }
        expect(ssp_member["methods"]).to include("GET", "PUT", "DELETE")
      end

      it "sees admin-only endpoints" do
        get "/api/v1/available", headers: admin_headers
        parsed = JSON.parse(response.body)
        endpoints = parsed["endpoints"]

        users_ep = endpoints.find { |e| e["path"] == "/api/v1/users" }
        expect(users_ep).to be_present
        expect(users_ep["methods"]).to include("GET", "POST")
      end
    end

    context "as a read-only user" do
      let(:reader) { create(:user) }
      let(:read_role) do
        create(:role, :authorization_boundary_scoped, permissions: {
          "ssp.read" => true,
          "sar.read" => true,
          "catalogs.read" => true
        })
      end
      let!(:user_role) { create(:user_role, user: reader, role: read_role, authorization_boundary_id: boundary.id) }
      let(:reader_token) { ApiToken.generate!(user: reader, name: "Reader Token") }
      let(:reader_headers) { { "Authorization" => "Bearer #{reader_token.plaintext_token}" } }

      it "sees only GET methods for permitted resources" do
        get "/api/v1/available", headers: reader_headers
        parsed = JSON.parse(response.body)
        endpoints = parsed["endpoints"]

        ssp_collection = endpoints.find { |e| e["path"] == "/api/v1/ssp_documents" }
        expect(ssp_collection).to be_present
        expect(ssp_collection["methods"]).to eq(%w[GET])
      end

      it "does not see admin-only endpoints" do
        get "/api/v1/available", headers: reader_headers
        parsed = JSON.parse(response.body)
        endpoints = parsed["endpoints"]

        users_ep = endpoints.find { |e| e["path"] == "/api/v1/users" }
        expect(users_ep).to be_nil
      end

      it "does not see resources with no permissions" do
        get "/api/v1/available", headers: reader_headers
        parsed = JSON.parse(response.body)
        endpoints = parsed["endpoints"]

        poam_ep = endpoints.find { |e| e["path"] == "/api/v1/poam_documents" }
        expect(poam_ep).to be_nil
      end

      it "always sees the discovery endpoint" do
        get "/api/v1/available", headers: reader_headers
        parsed = JSON.parse(response.body)
        endpoints = parsed["endpoints"]

        discovery = endpoints.find { |e| e["path"] == "/api/v1/available" }
        expect(discovery).to be_present
        expect(discovery["methods"]).to eq(%w[GET])
      end
    end

    context "as a write user" do
      let(:writer) { create(:user) }
      let(:write_role) do
        create(:role, :authorization_boundary_scoped, permissions: {
          "ssp.read" => true,
          "ssp.write" => true,
          "profiles.read" => true,
          "profiles.write" => true
        })
      end
      let!(:user_role) { create(:user_role, user: writer, role: write_role, authorization_boundary_id: boundary.id) }
      let(:writer_token) { ApiToken.generate!(user: writer, name: "Writer Token") }
      let(:writer_headers) { { "Authorization" => "Bearer #{writer_token.plaintext_token}" } }

      it "sees GET and write methods for permitted resources" do
        get "/api/v1/available", headers: writer_headers
        parsed = JSON.parse(response.body)
        endpoints = parsed["endpoints"]

        ssp_collection = endpoints.find { |e| e["path"] == "/api/v1/ssp_documents" }
        expect(ssp_collection["methods"]).to include("GET", "POST")

        ssp_member = endpoints.find { |e| e["path"] == "/api/v1/ssp_documents/:slug" }
        expect(ssp_member["methods"]).to include("GET", "PUT", "DELETE")
      end

      it "does not see write methods for admin-only resources" do
        get "/api/v1/available", headers: writer_headers
        parsed = JSON.parse(response.body)
        endpoints = parsed["endpoints"]

        # Catalogs are admin-only for writes
        catalogs_ep = endpoints.find { |e| e["path"] == "/api/v1/control_catalogs" }
        expect(catalogs_ep).to be_nil # No catalogs.read permission either
      end
    end

    context "as a user with no permissions" do
      let(:no_perm_user) { create(:user) }
      let(:no_perm_token) { ApiToken.generate!(user: no_perm_user, name: "No Perm Token") }
      let(:no_perm_headers) { { "Authorization" => "Bearer #{no_perm_token.plaintext_token}" } }

      it "sees only the discovery endpoint" do
        get "/api/v1/available", headers: no_perm_headers
        parsed = JSON.parse(response.body)
        endpoints = parsed["endpoints"]

        # Only discovery (nil permissions = always visible)
        expect(endpoints.length).to eq(1)
        expect(endpoints.first["path"]).to eq("/api/v1/available")
      end
    end

    it "includes endpoint descriptions" do
      get "/api/v1/available", headers: admin_headers
      parsed = JSON.parse(response.body)
      endpoints = parsed["endpoints"]

      endpoints.each do |ep|
        expect(ep["description"]).to be_present
        expect(ep["path"]).to start_with("/api/v1/")
        expect(ep["methods"]).to be_an(Array)
        expect(ep["methods"]).not_to be_empty
      end
    end
  end
end
