# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::PoamDocuments", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:api_token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }
  let(:boundary) { create(:authorization_boundary) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  describe "authentication" do
    it "returns 401 without a token" do
      get api_v1_poam_documents_path
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/poam_documents" do
    it "returns paginated list for admin" do
      create_list(:poam_document, 2, authorization_boundary: boundary)

      get api_v1_poam_documents_path, headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(2)
      expect(parsed["meta"]).to include("page", "count")
    end

    context "as a boundary-scoped user" do
      let(:boundary_user) { create(:user) }
      let(:boundary_role) { create(:role, :authorization_boundary_scoped, permissions: { "poam.read" => true }) }
      let!(:user_role) { create(:user_role, user: boundary_user, role: boundary_role, authorization_boundary_id: boundary.id) }
      let(:boundary_token) { ApiToken.generate!(user: boundary_user, name: "Boundary Token") }
      let(:boundary_headers) { { "Authorization" => "Bearer #{boundary_token.plaintext_token}" } }

      it "sees only documents in their boundary" do
        create(:poam_document, authorization_boundary: boundary)
        create(:poam_document, authorization_boundary: create(:authorization_boundary))

        get api_v1_poam_documents_path, headers: boundary_headers
        parsed = JSON.parse(response.body)
        expect(parsed["data"].length).to eq(1)
      end
    end
  end

  describe "GET /api/v1/poam_documents/:id" do
    it "returns detailed document" do
      poam = create(:poam_document, authorization_boundary: boundary)

      get api_v1_poam_document_path(poam), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["id"]).to eq(poam.id)
      expect(parsed["data"]).to have_key("items_count")
      expect(parsed["data"]).to have_key("risks_count")
    end
  end

  describe "POST /api/v1/poam_documents" do
    it "creates a document as admin" do
      expect {
        post api_v1_poam_documents_path, params: {
          poam_document: { name: "New POA&M", authorization_boundary_id: boundary.id }
        }, headers: auth_headers, as: :json
      }.to change(PoamDocument, :count).by(1)

      expect(response).to have_http_status(:created)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["name"]).to eq("New POA&M")
    end

    it "creates an audit event" do
      expect {
        post api_v1_poam_documents_path, params: {
          poam_document: { name: "Audited POA&M", authorization_boundary_id: boundary.id }
        }, headers: auth_headers, as: :json
      }.to change(AuditEvent, :count).by(1)
    end

    context "as a non-admin without write permission" do
      let(:reader_user) { create(:user) }
      let(:read_role) { create(:role, :authorization_boundary_scoped, permissions: { "poam.read" => true, "poam.write" => false }) }
      let!(:user_role) { create(:user_role, user: reader_user, role: read_role, authorization_boundary_id: boundary.id) }
      let(:reader_token) { ApiToken.generate!(user: reader_user, name: "Reader Token") }
      let(:reader_headers) { { "Authorization" => "Bearer #{reader_token.plaintext_token}" } }

      it "returns 403" do
        post api_v1_poam_documents_path, params: {
          poam_document: { name: "Denied POA&M" }
        }, headers: reader_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PUT /api/v1/poam_documents/:id" do
    it "updates a document as admin" do
      poam = create(:poam_document, authorization_boundary: boundary)

      put api_v1_poam_document_path(poam), params: {
        poam_document: { name: "Updated POA&M" }
      }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["name"]).to eq("Updated POA&M")
    end

    it "emits a poam_document_updated audit event (#433 slice 5)" do
      poam = create(:poam_document, authorization_boundary: boundary)
      assert_audit_event(
        action: "poam_document_updated",
        subject_type: "PoamDocument",
        metadata: { name: "Updated POA&M" }
      ) do
        put api_v1_poam_document_path(poam), params: {
          poam_document: { name: "Updated POA&M" }
        }, headers: auth_headers, as: :json
      end
    end
  end

  describe "DELETE /api/v1/poam_documents/:id" do
    it "soft-deletes the document" do
      poam = create(:poam_document, authorization_boundary: boundary)

      delete api_v1_poam_document_path(poam), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["deleted"]).to be true
      expect(PoamDocument.find_by(id: poam.id)).to be_nil
      expect(PoamDocument.with_deleted.find_by(id: poam.id)).to be_present
    end

    it "emits a poam_document_deleted audit event (#433 slice 5)" do
      poam = create(:poam_document, authorization_boundary: boundary)
      assert_audit_event(
        action: "poam_document_deleted",
        subject_type: "PoamDocument",
        metadata: { name: poam.name }
      ) do
        delete api_v1_poam_document_path(poam), headers: auth_headers
      end
    end
  end
end
