# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::CdefDocuments", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:api_token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  describe "authentication" do
    it "returns 401 without a token" do
      get api_v1_cdef_documents_path
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/cdef_documents" do
    it "returns paginated list" do
      create_list(:cdef_document, 3)

      get api_v1_cdef_documents_path, headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(3)
      expect(parsed["meta"]).to include("page", "count")
    end

    it "filters by cdef_type" do
      create(:cdef_document, cdef_type: "disa_stig")
      create(:cdef_document, cdef_type: "cis")

      get api_v1_cdef_documents_path, params: { cdef_type: "disa_stig" }, headers: auth_headers
      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(1)
    end

    it "filters by name" do
      create(:cdef_document, name: "RHEL 9 STIG")
      create(:cdef_document, name: "Windows Server CIS")

      get api_v1_cdef_documents_path, params: { name: "RHEL" }, headers: auth_headers
      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(1)
    end

    context "as a non-admin user" do
      let(:regular_user) { create(:user) }
      let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
      let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

      it "can read cdefs" do
        create(:cdef_document)

        get api_v1_cdef_documents_path, headers: user_headers
        expect(response).to have_http_status(:ok)
        parsed = JSON.parse(response.body)
        expect(parsed["data"].length).to eq(1)
      end
    end
  end

  describe "GET /api/v1/cdef_documents/:id" do
    it "returns detailed cdef" do
      cdef = create(:cdef_document)

      get api_v1_cdef_document_path(cdef), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["id"]).to eq(cdef.id)
      expect(parsed["data"]).to have_key("controls_count")
      expect(parsed["data"]).to have_key("description")
      expect(parsed["data"]).to have_key("oscal_version")
    end
  end

  describe "POST /api/v1/cdef_documents" do
    it "creates a cdef" do
      expect {
        post api_v1_cdef_documents_path, params: {
          cdef_document: {
            name: "New CDEF",
            cdef_type: "custom",
            cdef_version: "1.0.0"
          }
        }, headers: auth_headers, as: :json
      }.to change(CdefDocument, :count).by(1)

      expect(response).to have_http_status(:created)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["name"]).to eq("New CDEF")
    end

    it "creates an audit event" do
      expect {
        post api_v1_cdef_documents_path, params: {
          cdef_document: { name: "Audited CDEF", cdef_type: "custom" }
        }, headers: auth_headers, as: :json
      }.to change(AuditEvent, :count).by(1)
    end

    context "as a non-admin user" do
      let(:regular_user) { create(:user) }
      let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
      let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

      it "can create cdefs (all authenticated)" do
        post api_v1_cdef_documents_path, params: {
          cdef_document: { name: "User CDEF", cdef_type: "custom" }
        }, headers: user_headers, as: :json
        expect(response).to have_http_status(:created)
      end
    end
  end

  describe "PUT /api/v1/cdef_documents/:id" do
    it "updates a cdef" do
      cdef = create(:cdef_document)

      put api_v1_cdef_document_path(cdef), params: {
        cdef_document: { name: "Updated CDEF", cdef_version: "2.0.0" }
      }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["name"]).to eq("Updated CDEF")
    end
  end

  describe "DELETE /api/v1/cdef_documents/:id" do
    it "soft-deletes the cdef" do
      cdef = create(:cdef_document)

      delete api_v1_cdef_document_path(cdef), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["deleted"]).to be true
      expect(CdefDocument.find_by(id: cdef.id)).to be_nil
      expect(CdefDocument.with_deleted.find_by(id: cdef.id)).to be_present
    end
  end
end
