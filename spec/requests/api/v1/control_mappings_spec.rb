# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::ControlMappings", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:api_token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }
  let(:source_catalog) { create(:control_catalog) }
  let(:target_catalog) { create(:control_catalog) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  describe "authentication" do
    it "returns 401 without a token" do
      get api_v1_control_mappings_path
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/control_mappings" do
    it "returns paginated list" do
      create_list(:control_mapping, 3)

      get api_v1_control_mappings_path, headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(3)
      expect(parsed["meta"]).to include("page", "count")
    end

    it "filters by status" do
      create(:control_mapping, :complete)
      create(:control_mapping, status: "draft")

      get api_v1_control_mappings_path, params: { status: "complete" }, headers: auth_headers
      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(1)
    end

    it "filters by source_catalog_id" do
      create(:control_mapping, source_catalog: source_catalog)
      create(:control_mapping)

      get api_v1_control_mappings_path, params: { source_catalog_id: source_catalog.id }, headers: auth_headers
      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(1)
    end

    context "as a non-admin user" do
      let(:regular_user) { create(:user) }
      let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
      let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

      it "can read mappings" do
        create(:control_mapping)

        get api_v1_control_mappings_path, headers: user_headers
        expect(response).to have_http_status(:ok)
        parsed = JSON.parse(response.body)
        expect(parsed["data"].length).to eq(1)
      end
    end
  end

  describe "GET /api/v1/control_mappings/:id" do
    it "returns detailed mapping" do
      mapping = create(:control_mapping, source_catalog: source_catalog, target_catalog: target_catalog)

      get api_v1_control_mapping_path(mapping), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["id"]).to eq(mapping.id)
      expect(parsed["data"]).to have_key("entries_count")
      expect(parsed["data"]).to have_key("description")
      expect(parsed["data"]["source_catalog"]).to include("id", "name", "slug")
      expect(parsed["data"]["target_catalog"]).to include("id", "name", "slug")
    end
  end

  describe "POST /api/v1/control_mappings" do
    it "creates a mapping as admin" do
      expect {
        post api_v1_control_mappings_path, params: {
          control_mapping: {
            name: "New Mapping",
            status: "draft",
            method_type: "human",
            matching_rationale: "semantic",
            source_catalog_id: source_catalog.id,
            target_catalog_id: target_catalog.id
          }
        }, headers: auth_headers, as: :json
      }.to change(ControlMapping, :count).by(1)

      expect(response).to have_http_status(:created)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["name"]).to eq("New Mapping")
    end

    it "creates an audit event" do
      expect {
        post api_v1_control_mappings_path, params: {
          control_mapping: {
            name: "Audited Mapping",
            source_catalog_id: source_catalog.id,
            target_catalog_id: target_catalog.id
          }
        }, headers: auth_headers, as: :json
      }.to change(AuditEvent, :count).by(1)
    end

    context "as a non-admin user" do
      let(:regular_user) { create(:user) }
      let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
      let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

      it "returns 403" do
        post api_v1_control_mappings_path, params: {
          control_mapping: {
            name: "Denied Mapping",
            source_catalog_id: source_catalog.id,
            target_catalog_id: target_catalog.id
          }
        }, headers: user_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "PUT /api/v1/control_mappings/:id" do
    it "updates a mapping as admin" do
      mapping = create(:control_mapping)

      put api_v1_control_mapping_path(mapping), params: {
        control_mapping: { name: "Updated Mapping", status: "complete" }
      }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["name"]).to eq("Updated Mapping")
    end

    it "emits a control_mapping_updated audit event (#433 slice 5)" do
      mapping = create(:control_mapping)
      assert_audit_event(
        action: "control_mapping_updated",
        subject_type: "ControlMapping",
        metadata: { name: "Updated Mapping" }
      ) do
        put api_v1_control_mapping_path(mapping), params: {
          control_mapping: { name: "Updated Mapping" }
        }, headers: auth_headers, as: :json
      end
    end

    context "as a non-admin user" do
      let(:regular_user) { create(:user) }
      let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
      let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

      it "returns 403" do
        mapping = create(:control_mapping)
        put api_v1_control_mapping_path(mapping), params: {
          control_mapping: { name: "Denied Update" }
        }, headers: user_headers, as: :json
        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "DELETE /api/v1/control_mappings/:id" do
    it "hard-deletes the mapping" do
      mapping = create(:control_mapping)

      expect {
        delete api_v1_control_mapping_path(mapping), headers: auth_headers
      }.to change(ControlMapping, :count).by(-1)

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["deleted"]).to be true
    end

    it "emits a control_mapping_deleted audit event (#433 slice 5)" do
      mapping = create(:control_mapping)
      mapping_name = mapping.name
      assert_audit_event(
        action: "control_mapping_deleted",
        subject_type: "ControlMapping",
        metadata: { name: mapping_name }
      ) do
        delete api_v1_control_mapping_path(mapping), headers: auth_headers
      end
    end

    it "cascades to entries" do
      mapping = create(:control_mapping)
      create(:control_mapping_entry, control_mapping: mapping)

      expect {
        delete api_v1_control_mapping_path(mapping), headers: auth_headers
      }.to change(ControlMappingEntry, :count).by(-1)
    end

    context "as a non-admin user" do
      let(:regular_user) { create(:user) }
      let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
      let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

      it "returns 403" do
        mapping = create(:control_mapping)
        delete api_v1_control_mapping_path(mapping), headers: user_headers
        expect(response).to have_http_status(:forbidden)
      end
    end
  end
end
