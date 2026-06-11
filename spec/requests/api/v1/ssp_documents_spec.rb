# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::SspDocuments", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:api_token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }
  let(:boundary) { create(:authorization_boundary) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  # --- Authentication ---

  describe "authentication" do
    it "returns 401 without a token" do
      get api_v1_ssp_documents_path
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 401 with an invalid token" do
      get api_v1_ssp_documents_path, headers: { "Authorization" => "Bearer invalid_token" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # --- Index ---

  describe "GET /api/v1/ssp_documents" do
    it "returns paginated list for admin" do
      create_list(:ssp_document, 3, authorization_boundary: boundary)

      get api_v1_ssp_documents_path, headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]).to be_an(Array)
      expect(parsed["data"].length).to eq(3)
      expect(parsed["meta"]).to include("page", "count")
    end

    it "filters by status" do
      create(:ssp_document, status: "completed", authorization_boundary: boundary)
      create(:ssp_document, status: "pending", authorization_boundary: boundary)

      get api_v1_ssp_documents_path, params: { status: "completed" }, headers: auth_headers
      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(1)
      expect(parsed["data"].first["status"]).to eq("completed")
    end

    context "as a boundary-scoped user" do
      let(:boundary_user) { create(:user) }
      let(:boundary_role) { create(:role, :authorization_boundary_scoped, permissions: { "ssp.read" => true, "ssp.write" => true }) }
      let!(:user_role) { create(:user_role, user: boundary_user, role: boundary_role, authorization_boundary_id: boundary.id) }
      let(:boundary_token) { ApiToken.generate!(user: boundary_user, name: "Boundary Token") }
      let(:boundary_headers) { { "Authorization" => "Bearer #{boundary_token.plaintext_token}" } }

      it "sees only documents in their boundary" do
        create(:ssp_document, authorization_boundary: boundary)
        other_boundary = create(:authorization_boundary)
        create(:ssp_document, authorization_boundary: other_boundary)

        get api_v1_ssp_documents_path, headers: boundary_headers
        parsed = JSON.parse(response.body)
        expect(parsed["data"].length).to eq(1)
      end
    end
  end

  # --- Show ---

  describe "GET /api/v1/ssp_documents/:id" do
    it "returns detailed document for admin" do
      ssp = create(:ssp_document, authorization_boundary: boundary)

      get api_v1_ssp_document_path(ssp), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["id"]).to eq(ssp.id)
      expect(parsed["data"]["slug"]).to eq(ssp.slug)
      expect(parsed["data"]).to have_key("controls_count")
    end

    it "returns 404 for nonexistent document" do
      get api_v1_ssp_document_path(id: "nonexistent-slug"), headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  # --- Create ---

  describe "POST /api/v1/ssp_documents" do
    it "creates a document as admin" do
      expect {
        post api_v1_ssp_documents_path, params: {
          ssp_document: { name: "New SSP", authorization_boundary_id: boundary.id }
        }, headers: auth_headers, as: :json
      }.to change(SspDocument, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(response.headers["Location"]).to be_present

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["name"]).to eq("New SSP")
    end

    # #618 — fileless API create resolves to a terminal status via the shared
    # DocumentBaseController path, instead of hanging in `pending`.
    it "resolves a fileless create to completed (not stuck in pending)" do
      post api_v1_ssp_documents_path, params: {
        ssp_document: { name: "Fileless SSP", authorization_boundary_id: boundary.id }
      }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["data"]["status"]).to eq("completed")
    end

    it "creates an audit event" do
      expect {
        post api_v1_ssp_documents_path, params: {
          ssp_document: { name: "Audited SSP", authorization_boundary_id: boundary.id }
        }, headers: auth_headers, as: :json
      }.to change(AuditEvent, :count).by(1)

      expect(AuditEvent.last.action).to eq("ssp_document_created")
    end

    context "as a non-admin without write permission" do
      let(:reader_user) { create(:user) }
      let(:read_role) { create(:role, :authorization_boundary_scoped, permissions: { "ssp.read" => true, "ssp.write" => false }) }
      let!(:user_role) { create(:user_role, user: reader_user, role: read_role, authorization_boundary_id: boundary.id) }
      let(:reader_token) { ApiToken.generate!(user: reader_user, name: "Reader Token") }
      let(:reader_headers) { { "Authorization" => "Bearer #{reader_token.plaintext_token}" } }

      it "returns 403" do
        post api_v1_ssp_documents_path, params: {
          ssp_document: { name: "Denied SSP", authorization_boundary_id: boundary.id }
        }, headers: reader_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # --- Update ---

  describe "PUT /api/v1/ssp_documents/:id" do
    it "updates a document as admin" do
      ssp = create(:ssp_document, authorization_boundary: boundary)

      put api_v1_ssp_document_path(ssp), params: {
        ssp_document: { name: "Updated SSP" }
      }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["name"]).to eq("Updated SSP")
    end

    it "emits an ssp_document_updated audit event (#433 slice 5)" do
      ssp = create(:ssp_document, authorization_boundary: boundary)
      assert_audit_event(
        action: "ssp_document_updated",
        subject_type: "SspDocument",
        metadata: { name: "Updated SSP" }
      ) do
        put api_v1_ssp_document_path(ssp), params: {
          ssp_document: { name: "Updated SSP" }
        }, headers: auth_headers, as: :json
      end
    end
  end

  # --- Destroy (soft-delete) ---

  describe "DELETE /api/v1/ssp_documents/:id" do
    it "soft-deletes the document" do
      ssp = create(:ssp_document, authorization_boundary: boundary)

      delete api_v1_ssp_document_path(ssp), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["deleted"]).to be true

      # Document no longer visible in default scope
      expect(SspDocument.find_by(id: ssp.id)).to be_nil
      expect(SspDocument.with_deleted.find_by(id: ssp.id)).to be_present
    end

    it "emits an ssp_document_deleted audit event (#433 slice 5)" do
      ssp = create(:ssp_document, authorization_boundary: boundary)
      assert_audit_event(
        action: "ssp_document_deleted",
        subject_type: "SspDocument",
        metadata: { name: ssp.name }
      ) do
        delete api_v1_ssp_document_path(ssp), headers: auth_headers
      end
    end

    it "soft-deleted document returns 404 on show" do
      ssp = create(:ssp_document, authorization_boundary: boundary)
      ssp.soft_delete!

      get api_v1_ssp_document_path(ssp.slug), headers: auth_headers
      expect(response).to have_http_status(:not_found)
    end
  end

  # --- Legacy Actions ---

  describe "GET /api/v1/ssp_documents/:id/export" do
    it "returns JSON export" do
      ssp = create(:ssp_document, authorization_boundary: boundary)
      get export_api_v1_ssp_document_path(ssp), headers: auth_headers
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
    end

    it "returns 401 without auth (security fix)" do
      ssp = create(:ssp_document)
      get export_api_v1_ssp_document_path(ssp)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PUT /api/v1/ssp_documents/:id/update_fields" do
    it "updates control fields with auth" do
      ssp = create(:ssp_document, authorization_boundary: boundary)
      control = create(:ssp_control, ssp_document: ssp, control_id: "ac-1")
      create(:ssp_control_field, ssp_control: control, field_name: "status", field_value: "draft", editable: true)

      put update_fields_api_v1_ssp_document_path(ssp), params: {
        controls: { "ac-1" => { "status" => "implemented" } }
      }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["success"]).to be true
    end
  end

  describe "POST /api/v1/ssp_documents/convert" do
    it "rejects request without file" do
      post convert_api_v1_ssp_documents_path, headers: auth_headers, as: :json
      expect(response).to have_http_status(:bad_request)
      parsed = JSON.parse(response.body)
      expect(parsed["error"]).to include("No file provided")
    end

    it "returns 401 without auth (security fix)" do
      post convert_api_v1_ssp_documents_path, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end
end
