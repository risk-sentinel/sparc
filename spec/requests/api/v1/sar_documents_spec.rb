# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SarDocuments", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:api_token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }
  let(:boundary) { create(:authorization_boundary) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  describe "authentication" do
    it "returns 401 without a token" do
      get api_v1_sar_documents_path
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/sar_documents" do
    it "returns paginated list for admin" do
      create_list(:sar_document, 2, authorization_boundary: boundary)

      get api_v1_sar_documents_path, headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(2)
      expect(parsed["meta"]).to include("page", "count")
    end

    context "as a boundary-scoped user" do
      let(:boundary_user) { create(:user) }
      let(:boundary_role) { create(:role, :authorization_boundary_scoped, permissions: { "sar.read" => true }) }
      let!(:user_role) { create(:user_role, user: boundary_user, role: boundary_role, authorization_boundary_id: boundary.id) }
      let(:boundary_token) { ApiToken.generate!(user: boundary_user, name: "Boundary Token") }
      let(:boundary_headers) { { "Authorization" => "Bearer #{boundary_token.plaintext_token}" } }

      it "sees only documents in their boundary" do
        create(:sar_document, authorization_boundary: boundary)
        create(:sar_document, authorization_boundary: create(:authorization_boundary))

        get api_v1_sar_documents_path, headers: boundary_headers
        parsed = JSON.parse(response.body)
        expect(parsed["data"].length).to eq(1)
      end
    end
  end

  describe "GET /api/v1/sar_documents/:id" do
    it "returns detailed document" do
      sar = create(:sar_document, authorization_boundary: boundary)

      get api_v1_sar_document_path(sar), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["id"]).to eq(sar.id)
      expect(parsed["data"]).to have_key("controls_count")
    end
  end

  describe "POST /api/v1/sar_documents" do
    it "creates a document as admin" do
      expect {
        post api_v1_sar_documents_path, params: {
          sar_document: { name: "New SAR", authorization_boundary_id: boundary.id }
        }, headers: auth_headers, as: :json
      }.to change(SarDocument, :count).by(1)

      expect(response).to have_http_status(:created)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["name"]).to eq("New SAR")
    end

    it "creates an audit event" do
      expect {
        post api_v1_sar_documents_path, params: {
          sar_document: { name: "Audited SAR", authorization_boundary_id: boundary.id }
        }, headers: auth_headers, as: :json
      }.to change(AuditEvent, :count).by(1)
    end

    context "as a non-admin without write permission" do
      let(:reader_user) { create(:user) }
      let(:read_role) { create(:role, :authorization_boundary_scoped, permissions: { "sar.read" => true, "sar.write" => false }) }
      let!(:user_role) { create(:user_role, user: reader_user, role: read_role, authorization_boundary_id: boundary.id) }
      let(:reader_token) { ApiToken.generate!(user: reader_user, name: "Reader Token") }
      let(:reader_headers) { { "Authorization" => "Bearer #{reader_token.plaintext_token}" } }

      it "returns 403" do
        post api_v1_sar_documents_path, params: {
          sar_document: { name: "Denied SAR" }
        }, headers: reader_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PUT /api/v1/sar_documents/:id" do
    it "updates a document as admin" do
      sar = create(:sar_document, authorization_boundary: boundary)

      put api_v1_sar_document_path(sar), params: {
        sar_document: { name: "Updated SAR" }
      }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["name"]).to eq("Updated SAR")
    end

    it "emits a sar_document_updated audit event (#433 slice 5)" do
      sar = create(:sar_document, authorization_boundary: boundary)
      assert_audit_event(
        action: "sar_document_updated",
        subject_type: "SarDocument",
        metadata: { name: "Updated SAR" }
      ) do
        put api_v1_sar_document_path(sar), params: {
          sar_document: { name: "Updated SAR" }
        }, headers: auth_headers, as: :json
      end
    end
  end

  describe "DELETE /api/v1/sar_documents/:id" do
    it "soft-deletes the document" do
      sar = create(:sar_document, authorization_boundary: boundary)

      delete api_v1_sar_document_path(sar), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["deleted"]).to be true
      expect(SarDocument.find_by(id: sar.id)).to be_nil
      expect(SarDocument.with_deleted.find_by(id: sar.id)).to be_present
    end

    it "emits a sar_document_deleted audit event (#433 slice 5)" do
      sar = create(:sar_document, authorization_boundary: boundary)
      assert_audit_event(
        action: "sar_document_deleted",
        subject_type: "SarDocument",
        metadata: { name: sar.name }
      ) do
        delete api_v1_sar_document_path(sar), headers: auth_headers
      end
    end
  end

  # --- Legacy Actions ---

  describe "POST /api/v1/sar_documents/convert" do
    it "rejects request without file" do
      post convert_api_v1_sar_documents_path, headers: auth_headers, as: :json
      expect(response).to have_http_status(:bad_request)
    end

    it "returns 401 without auth" do
      post convert_api_v1_sar_documents_path, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
