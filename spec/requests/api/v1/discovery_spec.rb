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
      # #1233 — every /api/v1 route, not the 45 a hand-kept registry listed.
      it "sees every API route" do
        get "/api/v1/available", headers: admin_headers
        listed = JSON.parse(response.body)["endpoints"].map { |e| e["path"] }

        expected = ApiEndpointCatalog.routes.map do |r|
          path = r.spec.delete_suffix("(.:format)")
          Api::V1::DiscoveryController::LEGACY_PATHS.fetch(path, path)
        end.uniq
        expect(listed).to match_array(expected)
        expect(listed.size).to be > 150
      end

      # sparc-iac matches on these; the registry's spelling is kept.
      it "keeps the paths the registry listed, spelled as it spelled them" do
        get "/api/v1/available", headers: admin_headers
        listed = JSON.parse(response.body)["endpoints"].index_by { |e| e["path"] }

        Api::V1::DiscoveryController::DESCRIPTIONS.each do |path, description|
          expect(listed[path]).to be_present, "#{path} is no longer listed"
          expect(listed[path]["description"]).to eq(description)
        end
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

        # Catalogs are listed by catalogs.read / catalogs.write; this user holds neither
        catalogs_ep = endpoints.find { |e| e["path"] == "/api/v1/control_catalogs" }
        expect(catalogs_ep).to be_nil
      end
    end

    # #1154 part 2 — control mappings were marked admin_only, hiding them from
    # the non-admin `mappings.write` holders the controller actually admits.
    context "as a non-admin holding mappings.write" do
      let(:mapper) do
        role = create(:role, name: "mapper_probe", scope: "instance",
                             permissions: { "mappings.read" => true, "mappings.write" => true })
        create(:user).tap { |u| create(:user_role, user: u, role: role) }
      end

      it "sees the control-mapping endpoints, including the export, with their write methods" do
        token = ApiToken.generate!(user: mapper, name: "Mapper")
        get "/api/v1/available", headers: { "Authorization" => "Bearer #{token.plaintext_token}" }

        endpoints = JSON.parse(response.body)["endpoints"].index_by { |e| e["path"] }
        expect(endpoints["/api/v1/control_mappings"]["methods"]).to include("GET", "POST")
        expect(endpoints["/api/v1/control_mappings/:id/export"]["methods"]).to eq([ "GET" ])
      end
    end

    context "as a user with no permissions" do
      let(:no_perm_user) { create(:user) }
      let(:no_perm_token) { ApiToken.generate!(user: no_perm_user, name: "No Perm Token") }
      let(:no_perm_headers) { { "Authorization" => "Bearer #{no_perm_token.plaintext_token}" } }

      it "sees discovery, and nothing that needs a permission it lacks" do
        get "/api/v1/available", headers: no_perm_headers
        paths = JSON.parse(response.body)["endpoints"].map { |e| e["path"] }

        expect(paths).to include("/api/v1/available")
        expect(paths).not_to include("/api/v1/ssp_documents", "/api/v1/poam_documents",
                                     "/api/v1/evidences", "/api/v1/users", "/api/v1/roles")
      end

      # #1233 — the table restates the controllers' checks, so what discovery
      # lists must actually answer. Every listed GET without a path parameter
      # is called with the same token; a 403 means the table is wrong.
      it "lists only GET routes this caller is actually allowed to call" do
        get "/api/v1/available", headers: no_perm_headers
        gets = JSON.parse(response.body)["endpoints"]
                   .select { |e| e["methods"].include?("GET") && !e["path"].include?(":") }
                   .map { |e| e["path"] }
        expect(gets).not_to be_empty

        gets.each do |path|
          get path, headers: no_perm_headers
          expect(response).not_to have_http_status(:forbidden), "discovery lists GET #{path}, which refused this caller"
        end
      end

      # The other direction: what it hides, it is refused.
      it "is refused what discovery hides" do
        %w[/api/v1/users /api/v1/roles /api/v1/service_accounts /api/v1/organizations /api/v1/evidences].each do |path|
          get path, headers: no_perm_headers
          expect(response).to have_http_status(:forbidden), "GET #{path} was allowed but discovery hides it"
        end
      end
    end

    # #1233 — discovery reads the token's own limits, with the check enforcement makes.
    context "with a token limited to one resource" do
      let(:limited_token) do
        ApiToken.generate!(user: admin, name: "Limited",
                           allowed_endpoints: [ "available:read", "ssp_documents:read" ])
      end

      it "lists only the routes the token may reach" do
        get "/api/v1/available", headers: { "Authorization" => "Bearer #{limited_token.plaintext_token}" }
        endpoints = JSON.parse(response.body)["endpoints"]

        expect(endpoints.map { |e| e["group"] }.uniq).to contain_exactly("available", "ssp_documents")
        ssp = endpoints.find { |e| e["path"] == "/api/v1/ssp_documents" }
        expect(ssp["methods"]).to eq(%w[GET]), "a Read limit must not advertise POST"
      end

      it "lists everything for the same caller when the token has no limits" do
        get "/api/v1/available", headers: admin_headers
        groups = JSON.parse(response.body)["endpoints"].map { |e| e["group"] }.uniq

        expect(groups.size).to eq(ApiEndpointCatalog.groups.size)
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
