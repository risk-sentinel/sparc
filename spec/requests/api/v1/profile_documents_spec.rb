# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::ProfileDocuments", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:api_token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  describe "authentication" do
    it "returns 401 without a token" do
      get api_v1_profile_documents_path
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/profile_documents" do
    it "returns paginated list" do
      create_list(:profile_document, 3)

      get api_v1_profile_documents_path, headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(3)
      expect(parsed["meta"]).to include("page", "count")
    end

    it "filters by baseline_level" do
      create(:profile_document, baseline_level: "HIGH")
      create(:profile_document, baseline_level: "LOW")

      get api_v1_profile_documents_path, params: { baseline_level: "HIGH" }, headers: auth_headers
      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(1)
    end

    it "filters by name" do
      create(:profile_document, name: "NIST HIGH Profile")
      create(:profile_document, name: "CIS Benchmark")

      get api_v1_profile_documents_path, params: { name: "NIST" }, headers: auth_headers
      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(1)
    end

    context "as a non-admin user" do
      let(:regular_user) { create(:user) }
      let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
      let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

      it "can read profiles" do
        create(:profile_document)

        get api_v1_profile_documents_path, headers: user_headers
        expect(response).to have_http_status(:ok)
        parsed = JSON.parse(response.body)
        expect(parsed["data"].length).to eq(1)
      end
    end
  end

  describe "GET /api/v1/profile_documents/:id" do
    it "returns detailed profile" do
      profile = create(:profile_document)

      get api_v1_profile_document_path(profile), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["id"]).to eq(profile.id)
      expect(parsed["data"]).to have_key("controls_count")
      expect(parsed["data"]).to have_key("description")
      expect(parsed["data"]).to have_key("catalog_name")
    end
  end

  describe "POST /api/v1/profile_documents" do
    it "creates a profile" do
      catalog = create(:control_catalog)

      expect {
        post api_v1_profile_documents_path, params: {
          profile_document: {
            name: "New Profile",
            baseline_level: "HIGH",
            control_catalog_id: catalog.id
          }
        }, headers: auth_headers, as: :json
      }.to change(ProfileDocument, :count).by(1)

      expect(response).to have_http_status(:created)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["name"]).to eq("New Profile")
    end

    it "creates an audit event" do
      expect {
        post api_v1_profile_documents_path, params: {
          profile_document: { name: "Audited Profile" }
        }, headers: auth_headers, as: :json
      }.to change(AuditEvent, :count).by(1)
    end

    context "as a non-admin user" do
      let(:regular_user) { create(:user) }
      let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
      let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

      it "can create profiles (all authenticated)" do
        post api_v1_profile_documents_path, params: {
          profile_document: { name: "User Profile" }
        }, headers: user_headers, as: :json
        expect(response).to have_http_status(:created)
      end
    end
  end

  describe "PUT /api/v1/profile_documents/:id" do
    it "updates a profile" do
      profile = create(:profile_document)

      put api_v1_profile_document_path(profile), params: {
        profile_document: { name: "Updated Profile", baseline_level: "MODERATE" }
      }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["name"]).to eq("Updated Profile")
    end
  end

  describe "DELETE /api/v1/profile_documents/:id" do
    it "soft-deletes the profile" do
      profile = create(:profile_document)

      delete api_v1_profile_document_path(profile), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["deleted"]).to be true
      expect(ProfileDocument.find_by(id: profile.id)).to be_nil
      expect(ProfileDocument.with_deleted.find_by(id: profile.id)).to be_present
    end
  end
end
