# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::KsiValidations", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:api_token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }

  let!(:boundary) { create(:authorization_boundary) }
  let!(:ksi_catalog) { create(:control_catalog, name: "FedRAMP 20x Key Security Indicators", source: "FedRAMP 20x") }
  let!(:theme) { create(:control_family, control_catalog: ksi_catalog, code: "IAM", name: "Identity and Access Management") }
  let!(:ksi_control) { create(:catalog_control, control_family: theme, control_id: "ksi-iam-01", title: "MFA") }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  describe "authentication" do
    it "returns 401 without a token" do
      get api_v1_authorization_boundary_ksi_validations_path(authorization_boundary_id: boundary.slug)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "GET /api/v1/authorization_boundaries/:id/ksi_validations" do
    it "returns paginated validations" do
      create(:ksi_validation, :passed, authorization_boundary: boundary, catalog_control: ksi_control)

      get api_v1_authorization_boundary_ksi_validations_path(authorization_boundary_id: boundary.slug),
        headers: auth_headers
      expect(response).to have_http_status(:ok)

      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(1)
      expect(parsed["data"].first["ksi_id"]).to eq("ksi-iam-01")
      expect(parsed["meta"]).to include("page", "count")
    end

    it "filters by status" do
      create(:ksi_validation, :passed, authorization_boundary: boundary, catalog_control: ksi_control)
      other_control = create(:catalog_control, control_family: theme, control_id: "ksi-iam-02")
      create(:ksi_validation, :failed, authorization_boundary: boundary, catalog_control: other_control)

      get api_v1_authorization_boundary_ksi_validations_path(authorization_boundary_id: boundary.slug),
        params: { status: "passed" }, headers: auth_headers

      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(1)
      expect(parsed["data"].first["status"]).to eq("passed")
    end

    it "filters by theme" do
      other_theme = create(:control_family, control_catalog: ksi_catalog, code: "MLA")
      other_control = create(:catalog_control, control_family: other_theme, control_id: "ksi-mla-01")
      create(:ksi_validation, authorization_boundary: boundary, catalog_control: ksi_control)
      create(:ksi_validation, authorization_boundary: boundary, catalog_control: other_control)

      get api_v1_authorization_boundary_ksi_validations_path(authorization_boundary_id: boundary.slug),
        params: { theme: "IAM" }, headers: auth_headers

      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(1)
      expect(parsed["data"].first["theme_code"]).to eq("IAM")
    end

    it "filters by overdue" do
      create(:ksi_validation, authorization_boundary: boundary, catalog_control: ksi_control,
        status: "not_assessed", next_validation_due: 1.day.ago)

      get api_v1_authorization_boundary_ksi_validations_path(authorization_boundary_id: boundary.slug),
        params: { overdue: "true" }, headers: auth_headers

      parsed = JSON.parse(response.body)
      expect(parsed["data"].length).to eq(1)
    end
  end

  describe "GET /api/v1/authorization_boundaries/:id/ksi_validations/:id" do
    it "returns validation details" do
      validation = create(:ksi_validation, :passed, :with_metadata,
        authorization_boundary: boundary, catalog_control: ksi_control, notes: "All good")

      get api_v1_authorization_boundary_ksi_validation_path(
        authorization_boundary_id: boundary.slug, id: validation.id), headers: auth_headers

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["ksi_id"]).to eq("ksi-iam-01")
      expect(parsed["data"]["notes"]).to eq("All good")
      expect(parsed["data"]["validation_metadata"]).to be_present
    end
  end

  describe "POST /api/v1/authorization_boundaries/:id/ksi_validations" do
    it "creates a validation" do
      expect {
        post api_v1_authorization_boundary_ksi_validations_path(authorization_boundary_id: boundary.slug),
          params: {
            ksi_validation: {
              catalog_control_id: ksi_control.id,
              status: "passed",
              validation_method: "automated",
              last_validated_at: Time.current.iso8601,
              next_validation_due: 7.days.from_now.iso8601,
              notes: "Okta MFA enforced"
            }
          },
          headers: auth_headers
      }.to change(KsiValidation, :count).by(1)

      expect(response).to have_http_status(:created)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["status"]).to eq("passed")
      expect(parsed["data"]["ksi_id"]).to eq("ksi-iam-01")
    end

    it "returns 422 for invalid data" do
      post api_v1_authorization_boundary_ksi_validations_path(authorization_boundary_id: boundary.slug),
        params: { ksi_validation: { catalog_control_id: ksi_control.id, status: "bogus" } },
        headers: auth_headers

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/authorization_boundaries/:id/ksi_validations/:id" do
    it "updates a validation" do
      validation = create(:ksi_validation, authorization_boundary: boundary, catalog_control: ksi_control)

      patch api_v1_authorization_boundary_ksi_validation_path(
        authorization_boundary_id: boundary.slug, id: validation.id),
        params: { ksi_validation: { status: "passed", validation_method: "manual" } },
        headers: auth_headers

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["status"]).to eq("passed")
    end
  end

  describe "DELETE /api/v1/authorization_boundaries/:id/ksi_validations/:id" do
    it "deletes as admin" do
      validation = create(:ksi_validation, authorization_boundary: boundary, catalog_control: ksi_control)

      expect {
        delete api_v1_authorization_boundary_ksi_validation_path(
          authorization_boundary_id: boundary.slug, id: validation.id),
          headers: auth_headers
      }.to change(KsiValidation, :count).by(-1)

      expect(response).to have_http_status(:ok)
    end

    context "as a non-admin user" do
      let(:regular_user) { create(:user) }
      let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
      let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

      it "returns 403" do
        validation = create(:ksi_validation, authorization_boundary: boundary, catalog_control: ksi_control)

        delete api_v1_authorization_boundary_ksi_validation_path(
          authorization_boundary_id: boundary.slug, id: validation.id),
          headers: user_headers

        expect(response).to have_http_status(:forbidden)
      end
    end
  end

  describe "GET /api/v1/authorization_boundaries/:id/ksi_validations/summary" do
    it "returns summary statistics" do
      create(:ksi_validation, :passed, authorization_boundary: boundary, catalog_control: ksi_control)
      other_control = create(:catalog_control, control_family: theme, control_id: "ksi-iam-02")
      create(:ksi_validation, :failed, authorization_boundary: boundary, catalog_control: other_control)

      get summary_api_v1_authorization_boundary_ksi_validations_path(
        authorization_boundary_id: boundary.slug), headers: auth_headers

      expect(response).to have_http_status(:ok)
      parsed = JSON.parse(response.body)
      expect(parsed["data"]["total"]).to eq(2)
      expect(parsed["data"]["by_status"]["passed"]).to eq(1)
      expect(parsed["data"]["by_status"]["failed"]).to eq(1)
      expect(parsed["data"]["compliance_percentage"]).to eq(50.0)
    end
  end

  describe "GET /api/v1/authorization_boundaries/:id/ksi_validations/export" do
    before do
      create(:ksi_validation, :passed, authorization_boundary: boundary, catalog_control: ksi_control)
    end

    it "exports as JSON by default" do
      get export_api_v1_authorization_boundary_ksi_validations_path(
        authorization_boundary_id: boundary.slug), headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/json")
      parsed = JSON.parse(response.body)
      expect(parsed["validations"]).to be_an(Array)
    end

    it "exports as YAML" do
      get export_api_v1_authorization_boundary_ksi_validations_path(
        authorization_boundary_id: boundary.slug), params: { format: "yaml" }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/x-yaml")
    end

    it "exports as XML" do
      get export_api_v1_authorization_boundary_ksi_validations_path(
        authorization_boundary_id: boundary.slug), params: { format: "xml" }, headers: auth_headers

      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("application/xml")
      expect(response.body).to include("ksi-compliance-report")
    end
  end

  context "as a non-admin user" do
    let(:regular_user) { create(:user) }
    let(:user_token) { ApiToken.generate!(user: regular_user, name: "User Token") }
    let(:user_headers) { { "Authorization" => "Bearer #{user_token.plaintext_token}" } }

    it "can read and create validations" do
      get api_v1_authorization_boundary_ksi_validations_path(authorization_boundary_id: boundary.slug),
        headers: user_headers
      expect(response).to have_http_status(:ok)

      post api_v1_authorization_boundary_ksi_validations_path(authorization_boundary_id: boundary.slug),
        params: {
          ksi_validation: { catalog_control_id: ksi_control.id, status: "not_assessed" }
        },
        headers: user_headers
      expect(response).to have_http_status(:created)
    end
  end
end
