# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::ControlCatalogs", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:api_token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  describe "authentication" do
    it "returns 401 without a token" do
      get api_v1_control_catalogs_path
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/control_catalogs" do
    it "returns paginated list" do
      create_list(:control_catalog, 3)

      get api_v1_control_catalogs_path, headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(3)
      expect(parsed["meta"]).to include("page", "count")
    end

    it "filters by status" do
      create(:control_catalog, status: :completed)
      create(:control_catalog, status: :pending)

      get api_v1_control_catalogs_path, params: { status: "completed" }, headers: auth_headers
      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(1)
    end

    it "filters by name" do
      create(:control_catalog, name: "NIST 800-53 Rev 5")
      create(:control_catalog, name: "ISO 27001")

      get api_v1_control_catalogs_path, params: { name: "NIST" }, headers: auth_headers
      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(1)
    end

    context "as a non-admin user" do
      let(:regular_user) { create(:user) }
      let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
      let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

      it "can read catalogs" do
        create(:control_catalog)

        get api_v1_control_catalogs_path, headers: user_headers
        expect(response).to have_http_status(:ok)
        parsed = JSON.parse(response.body)
        expect(parsed["data"].length).to eq(1)
      end
    end
  end

  describe "GET /api/v1/control_catalogs/:id" do
    it "returns detailed catalog" do
      catalog = create(:control_catalog, :with_families)

      get api_v1_control_catalog_path(catalog), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["id"]).to eq(catalog.id)
      expect(parsed["data"]).to have_key("total_controls")
      expect(parsed["data"]).to have_key("families_count")
      expect(parsed["data"]).to have_key("short_digest")
    end
  end

  describe "POST /api/v1/control_catalogs" do
    it "creates a catalog as admin" do
      expect {
        post api_v1_control_catalogs_path, params: {
          control_catalog: {
            name: "New Catalog",
            description: "Test catalog",
            version: "2.0.0",
            source: "OSCAL"
          }
        }, headers: auth_headers, as: :json
      }.to change(ControlCatalog, :count).by(1)

      expect(response).to have_http_status(:created)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["name"]).to eq("New Catalog")
    end

    it "creates an audit event" do
      expect {
        post api_v1_control_catalogs_path, params: {
          control_catalog: { name: "Audited Catalog" }
        }, headers: auth_headers, as: :json
      }.to change(AuditEvent, :count).by(1)
    end

    context "as a non-admin user" do
      let(:regular_user) { create(:user) }
      let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
      let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

      it "returns 403" do
        post api_v1_control_catalogs_path, params: {
          control_catalog: { name: "Denied Catalog" }
        }, headers: user_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PUT /api/v1/control_catalogs/:id" do
    it "updates a catalog as admin" do
      catalog = create(:control_catalog)

      put api_v1_control_catalog_path(catalog), params: {
        control_catalog: { name: "Updated Catalog", version: "3.0.0" }
      }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["name"]).to eq("Updated Catalog")
    end

    it "emits a control_catalog_updated audit event (#433 slice 5)" do
      catalog = create(:control_catalog)
      assert_audit_event(
        action: "control_catalog_updated",
        subject_type: "ControlCatalog",
        metadata: { name: "Updated Catalog" }
      ) do
        put api_v1_control_catalog_path(catalog), params: {
          control_catalog: { name: "Updated Catalog" }
        }, headers: auth_headers, as: :json
      end
    end

    context "as a non-admin user" do
      let(:regular_user) { create(:user) }
      let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
      let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

      it "returns 403" do
        catalog = create(:control_catalog)
        put api_v1_control_catalog_path(catalog), params: {
          control_catalog: { name: "Denied Update" }
        }, headers: user_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "DELETE /api/v1/control_catalogs/:id" do
    it "hard-deletes the catalog" do
      catalog = create(:control_catalog)

      delete api_v1_control_catalog_path(catalog), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["deleted"]).to be true
      expect(ControlCatalog.find_by(id: catalog.id)).to be_nil
    end

    it "emits a control_catalog_deleted audit event (#433 slice 5)" do
      catalog = create(:control_catalog)
      assert_audit_event(
        action: "control_catalog_deleted",
        subject_type: "ControlCatalog",
        metadata: { name: catalog.name }
      ) do
        delete api_v1_control_catalog_path(catalog), headers: auth_headers
      end
    end

    it "returns 422 if catalog has dependencies" do
      catalog = create(:control_catalog)
      create(:profile_document, control_catalog: catalog)

      delete api_v1_control_catalog_path(catalog), headers: auth_headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    context "as a non-admin user" do
      let(:regular_user) { create(:user) }
      let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
      let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

      it "returns 403" do
        catalog = create(:control_catalog)
        delete api_v1_control_catalog_path(catalog), headers: user_headers
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
