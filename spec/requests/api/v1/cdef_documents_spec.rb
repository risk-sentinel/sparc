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

    # #618 — a metadata-only API create has no file to parse, so it must NOT
    # linger in the schema-default `pending` (the "stuck document" bug). It
    # resolves to a terminal `completed` status on save.
    it "resolves a fileless create to completed (not stuck in pending)" do
      post api_v1_cdef_documents_path, params: {
        cdef_document: { name: "Fileless CDEF", cdef_type: "custom" }
      }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body)["data"]["status"]).to eq("completed")
      expect(CdefDocument.find_by(name: "Fileless CDEF").status).to eq("completed")
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

  # ── #499 slice 3 — bulk-apply Converter preview ─────────────────────
  describe "POST /api/v1/cdef_documents/:id/bulk_apply_converter/preview" do
    let(:cdef) { create(:cdef_document, name: "Bulk Apply Spec") }
    let(:converter) do
      conv = Converter.create!(name: "Spec Converter", converter_type: "custom",
                               status: "complete", metadata_extra: { "target_rev" => "5" })
      ConverterEntry.create!(converter: conv, source_id: "src-x", target_id: "ac-2",
                             relationship: "equivalent", row_order: 0)
      conv
    end
    let(:path) { "/api/v1/cdef_documents/#{cdef.slug}/bulk_apply_converter/preview" }

    it "returns the changeset + token for admin caller" do
      post path, params: { converter_id: converter.id }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["rows"].length).to eq(1)
      expect(data["rows"].first["target_id"]).to eq("ac-2")
      expect(data["token"]).to be_present
      expect(data["stats"]).to include("ready" => 1, "already_present" => 0)
    end

    it "returns 404 for an unknown converter_id" do
      post path, params: { converter_id: 999_999 }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:not_found)
    end

    it "returns 422 when the CDEF is AWS-Labs-sourced" do
      cdef.update!(import_metadata: { "source_type" => "aws_labs", "source_url" => "https://example/cdef.json" })
      post path, params: { converter_id: converter.id }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("clone first")
    end

    it "returns 401 without an API token" do
      post path, params: { converter_id: converter.id }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    context "as a non-admin user without converters.write" do
      let(:regular_user) { create(:user) }
      let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
      let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

      it "returns 403" do
        post path, params: { converter_id: converter.id }, headers: user_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end

    context "as a non-admin user WITH converters.write" do
      let(:regular_user) { create(:user) }
      let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
      let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }
      let(:writer_role) do
        Role.find_or_create_by!(name: "converter_writer", display_name: "Converter Writer",
                                scope: "instance", permissions: { "converters.write" => true })
      end

      before { regular_user.user_roles.create!(role: writer_role) }

      it "is authorized to preview" do
        post path, params: { converter_id: converter.id }, headers: user_headers, as: :json
        expect(response).to have_http_status(:ok)
      end
    end
  end

  # ── #499 slice 4 — bulk-apply Converter confirm ─────────────────────
  describe "POST /api/v1/cdef_documents/:id/bulk_apply_converter/confirm" do
    let(:cdef) { create(:cdef_document, name: "Confirm Spec") }
    let(:converter) do
      conv = Converter.create!(name: "Confirm Converter", converter_type: "custom",
                               status: "complete", metadata_extra: { "target_rev" => "5" })
      ConverterEntry.create!(converter: conv, source_id: "src-a", target_id: "au-2",
                             relationship: "equivalent", row_order: 0)
      conv
    end
    let(:preview_path) { "/api/v1/cdef_documents/#{cdef.slug}/bulk_apply_converter/preview" }
    let(:confirm_path) { "/api/v1/cdef_documents/#{cdef.slug}/bulk_apply_converter/confirm" }

    def fetch_token
      post preview_path, params: { converter_id: converter.id }, headers: auth_headers, as: :json
      JSON.parse(response.body).dig("data", "token")
    end

    it "applies the changeset and adds CdefControl rows" do
      token = fetch_token
      expect {
        post confirm_path, params: { token: token }, headers: auth_headers, as: :json
      }.to change { cdef.cdef_controls.count }.by(1)
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["added"]).to eq(1)
      expect(data["added_control_ids"]).to eq([ "au-2" ])
    end

    it "is idempotent — re-confirming the same token after apply doesn't add duplicates" do
      token = fetch_token
      post confirm_path, params: { token: token }, headers: auth_headers, as: :json

      # Re-preview (token from after the apply) + re-confirm.
      token2 = fetch_token
      expect {
        post confirm_path, params: { token: token2 }, headers: auth_headers, as: :json
      }.not_to change { cdef.cdef_controls.count }
    end

    it "rejects a token from a different CDEF" do
      token = fetch_token
      other = create(:cdef_document, name: "Other CDEF")
      post "/api/v1/cdef_documents/#{other.slug}/bulk_apply_converter/confirm",
           params: { token: token }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("CDEF mismatch")
    end

    it "rejects a tampered token" do
      token = fetch_token
      tampered = token.sub(/\.\w/, ".X")
      post confirm_path, params: { token: tampered }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["error"]).to include("signature invalid")
    end

    it "returns 422 when the CDEF is AWS-Labs-sourced" do
      token = fetch_token
      cdef.update!(import_metadata: { "source_type" => "aws_labs", "source_url" => "https://example/cdef.json" })
      post confirm_path, params: { token: token }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 401 without an API token" do
      post confirm_path, params: { token: "anything" }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    context "as a non-admin user without converters.write" do
      let(:regular_user) { create(:user) }
      let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
      let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

      it "returns 403" do
        post confirm_path, params: { token: "anything" }, headers: user_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  # #627/#628 — content-completeness exposed independently of the parse status.
  describe "serializer content-completeness" do
    it "reports an empty CDEF as content-incomplete despite status completed" do
      cdef = create(:cdef_document, status: "completed")

      get api_v1_cdef_document_path(cdef), headers: auth_headers
      parsed = JSON.parse(response.body)["data"]

      expect(parsed["status"]).to eq("completed")
      expect(parsed["content_complete"]).to be(false)
      expect(parsed["content_completeness_gaps"]).to include("At least one control")
    end
  end

  # #628 — populate an existing empty CDEF from a published profile.
  describe "POST /api/v1/cdef_documents/:id/populate_from_profile" do
    let(:resolved_catalog) do
      {
        "catalog" => {
          "uuid" => SecureRandom.uuid,
          "metadata" => { "title" => "Test", "oscal-version" => "1.1.2" },
          "groups" => [
            { "id" => "ac", "title" => "Access Control",
              "controls" => [
                { "id" => "ac-1", "title" => "Policy",
                  "props" => [ { "name" => "priority", "value" => "P1" } ],
                  "parts" => [ { "name" => "statement", "prose" => "Test statement" } ] }
              ] }
          ]
        }
      }
    end
    let(:profile) do
      create(:profile_document, lifecycle_status: "published",
        resolved_catalog_json: resolved_catalog, published: Time.current.iso8601)
    end

    it "populates an empty CDEF and returns it content-complete" do
      cdef = create(:cdef_document)

      post populate_from_profile_api_v1_cdef_document_path(cdef),
        params: { source_profile_id: profile.slug }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)["data"]
      expect(parsed["content_complete"]).to be(true)
      expect(cdef.reload.cdef_controls.count).to eq(1)
    end

    it "returns 422 when the CDEF already has controls" do
      cdef = create(:cdef_document)
      create(:cdef_control, cdef_document: cdef)

      post populate_from_profile_api_v1_cdef_document_path(cdef),
        params: { source_profile_id: profile.slug }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 404 for an unpublished profile" do
      cdef = create(:cdef_document)
      draft = create(:profile_document, lifecycle_status: "in_progress")

      post populate_from_profile_api_v1_cdef_document_path(cdef),
        params: { source_profile_id: draft.slug }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:not_found)
    end
  end
end
