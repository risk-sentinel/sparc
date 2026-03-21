# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::BaselineParameters", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:api_token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }

  let(:catalog) { create(:control_catalog) }
  let(:family) { create(:control_family, control_catalog: catalog, code: "AC") }
  let(:other_family) { create(:control_family, control_catalog: catalog, code: "AU") }
  let!(:control_with_params) do
    create(:catalog_control, :with_params,
      control_family: family,
      control_id: "ac-1",
      title: "Policy and Procedures")
  end
  let!(:control_with_select) do
    create(:catalog_control, :with_select_param,
      control_family: family,
      control_id: "ac-2",
      title: "Account Management")
  end
  let(:profile) { create(:profile_document, control_catalog: catalog) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  describe "authentication" do
    it "returns 401 without a token" do
      get api_v1_profile_document_parameters_path(profile)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/profile_documents/:id/parameters" do
    it "returns parameter schema" do
      get api_v1_profile_document_parameters_path(profile), headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"]["baseline"]).to eq(profile.name)
      expect(parsed["data"]["parameters"]).to be_an(Array)
      expect(parsed["data"]["selections"]).to be_an(Array)
      expect(parsed["data"]["parameters"].length).to eq(2)
      expect(parsed["data"]["selections"].length).to eq(1)
    end

    it "includes current values from profile_control_fields" do
      pc = create(:profile_control, profile_document: profile, control_id: "ac-1")
      pc.profile_control_fields.create!(
        field_name: "parameter:ac-1_prm_1",
        field_value: "System Admins"
      )

      get api_v1_profile_document_parameters_path(profile), headers: auth_headers
      parsed = JSON.parse(response.body)
      param = parsed["data"]["parameters"].find { |p| p["param_id"] == "ac-1_prm_1" }
      expect(param["current_value"]).to eq("System Admins")
    end

    it "filters by family" do
      create(:catalog_control, :with_params,
        control_family: other_family,
        control_id: "au-1",
        title: "Audit Policy")

      get api_v1_profile_document_parameters_path(profile),
        params: { family: family.code }, headers: auth_headers
      parsed = JSON.parse(response.body)
      control_ids = parsed["data"]["parameters"].map { |p| p["control_id"] }
      expect(control_ids).to all(start_with(family.code.downcase))
    end
  end

  describe "PUT /api/v1/profile_documents/:id/parameters" do
    before do
      create(:profile_control, profile_document: profile, control_id: "ac-1")
    end

    it "updates parameters and returns summary" do
      put api_v1_profile_document_parameters_path(profile), params: {
        parameters: [
          { param_id: "ac-1_prm_1", value: "ISSO" }
        ]
      }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["status"]).to eq("updated")
      expect(parsed["data"]["parameters_updated"]).to eq(1)
    end

    it "creates an audit event" do
      expect {
        put api_v1_profile_document_parameters_path(profile), params: {
          parameters: [
            { param_id: "ac-1_prm_1", value: "ISSO" }
          ]
        }, headers: auth_headers, as: :json
      }.to change(AuditEvent, :count).by(1)
    end

    it "returns 422 for unknown param_ids" do
      put api_v1_profile_document_parameters_path(profile), params: {
        parameters: [
          { param_id: "nonexistent", value: "test" }
        ]
      }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["validation_errors"]).not_to be_empty
    end
  end

  describe "GET /api/v1/profile_documents/:id/parameters/export" do
    it "exports as JSON by default" do
      get export_api_v1_profile_document_parameters_path(profile),
        headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
      parsed = JSON.parse(response.body)
      expect(parsed["baseline"]).to eq(profile.name)
    end

    it "exports as YAML" do
      get export_api_v1_profile_document_parameters_path(profile),
        params: { format: "yaml" }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/yaml")
    end

    it "exports as XML" do
      get export_api_v1_profile_document_parameters_path(profile),
        params: { format: "xml" }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/xml")
    end
  end

  describe "non-admin access" do
    let(:regular_user) { create(:user) }
    let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
    let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

    it "allows read access" do
      get api_v1_profile_document_parameters_path(profile), headers: user_headers
      expect(response).to have_http_status(:ok)
    end

    it "allows write access (all authenticated)" do
      create(:profile_control, profile_document: profile, control_id: "ac-1")

      put api_v1_profile_document_parameters_path(profile), params: {
        parameters: [
          { param_id: "ac-1_prm_1", value: "test" }
        ]
      }, headers: user_headers, as: :json
      expect(response).to have_http_status(:ok)
    end
  end
end
