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

    # Issue #549 — paginate() must honor ?items / ?per_page from the client.
    # Previously these were ignored and meta.items always reflected the
    # controller's hardcoded default.
    describe "pagination query params" do
      before { create_list(:cdef_document, 8) }

      it "honors ?items=N" do
        get api_v1_cdef_documents_path, params: { items: 3 }, headers: auth_headers
        parsed = JSON.parse(response.body)
        expect(parsed["data"].length).to eq(3)
        expect(parsed["meta"]["items"]).to eq(3)
      end

      it "honors ?per_page=N as an alias for ?items" do
        get api_v1_cdef_documents_path, params: { per_page: 2 }, headers: auth_headers
        parsed = JSON.parse(response.body)
        expect(parsed["data"].length).to eq(2)
        expect(parsed["meta"]["items"]).to eq(2)
      end

      it "clamps absurd ?items values to MAX_PAGINATION_LIMIT" do
        get api_v1_cdef_documents_path, params: { items: 999_999 }, headers: auth_headers
        parsed = JSON.parse(response.body)
        expect(parsed["meta"]["items"]).to eq(Api::V1::BaseController::MAX_PAGINATION_LIMIT)
      end

      it "falls back to default when ?items is non-positive or blank" do
        get api_v1_cdef_documents_path, params: { items: 0 }, headers: auth_headers
        expect(JSON.parse(response.body)["meta"]["items"]).to eq(25)

        get api_v1_cdef_documents_path, params: { items: "" }, headers: auth_headers
        expect(JSON.parse(response.body)["meta"]["items"]).to eq(25)
      end
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

    # Issue #466 — filter on import_metadata.source_type for AWS Labs inventory
    it "filters by source_type=aws_labs" do
      create(:cdef_document, name: "User CDEF")
      create(:cdef_document, name: "AWS S3", import_metadata: {
        "source_type" => "aws_labs",
        "source_url" => "https://github.com/awslabs/example/blob/main/s3.json",
        "source_sha" => "abc"
      })

      get api_v1_cdef_documents_path, params: { source_type: "aws_labs" }, headers: auth_headers
      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(1)
      expect(parsed["data"].first["name"]).to eq("AWS S3")
      expect(parsed["data"].first["source"]).to include("type" => "aws_labs", "sha" => "abc")
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

    it "emits a cdef_document_created audit event" do
      assert_audit_event(
        action: "cdef_document_created",
        subject_type: "CdefDocument",
        metadata: { name: "Audited CDEF" }
      ) do
        post api_v1_cdef_documents_path, params: {
          cdef_document: { name: "Audited CDEF", cdef_type: "custom" }
        }, headers: auth_headers, as: :json
      end
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

    it "emits a cdef_document_updated audit event (#433 slice 5)" do
      cdef = create(:cdef_document)
      assert_audit_event(
        action: "cdef_document_updated",
        subject_type: "CdefDocument",
        metadata: { name: "Updated CDEF" }
      ) do
        put api_v1_cdef_document_path(cdef), params: {
          cdef_document: { name: "Updated CDEF" }
        }, headers: auth_headers, as: :json
      end
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

    it "emits a cdef_document_deleted audit event (#433 slice 5)" do
      cdef = create(:cdef_document)
      assert_audit_event(
        action: "cdef_document_deleted",
        subject_type: "CdefDocument",
        metadata: { name: cdef.name }
      ) do
        delete api_v1_cdef_document_path(cdef), headers: auth_headers
      end
    end
  end
end
