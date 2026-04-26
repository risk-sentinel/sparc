# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Api::V1::Admin::Credentials", type: :request do
  let(:admin_email) { "admin@sparc.test" }
  let!(:admin) do
    User.create!(email: admin_email, password: "Initial-Pwd-1234",
                 password_confirmation: "Initial-Pwd-1234",
                 admin: true, status: "active", display_name: "Admin")
  end

  let(:rotation_role) do
    Role.find_or_create_by!(name: "rotation_lambda") do |r|
      r.display_name = "Rotation Lambda"
      r.scope = "instance"
      r.permissions = { "admin.rotate_credentials" => true }
    end
  end
  let(:service_account) do
    User.create!(
      email: "rotation-lambda@sparc.test",
      password: "Service-Account-Pwd-1234",
      password_confirmation: "Service-Account-Pwd-1234",
      admin: false, status: "active", display_name: "Rotation Lambda",
      service_account: true, owner: admin
    )
  end
  let!(:service_user_role) do
    UserRole.create!(user: service_account, role: rotation_role)
  end
  let(:lambda_token) { ApiToken.generate!(user: service_account, name: "Lambda Token") }
  let(:auth_headers) { { "Authorization" => "Bearer #{lambda_token.plaintext_token}" } }

  before do
    ENV["SPARC_ADMIN_EMAIL"] = admin_email
    ENV["SPARC_ADMIN_REFRESH_ENABLED"] = "true"
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  after do
    ENV.delete("SPARC_ADMIN_EMAIL")
    ENV.delete("SPARC_ADMIN_REFRESH_ENABLED")
  end

  describe "POST /api/v1/admin/refresh_credentials" do
    let(:path) { "/api/v1/admin/refresh_credentials" }

    it "rotates the admin password and returns 200 with audit_event_id" do
      post path, params: { password: "Brand-New-Password-99" }, headers: auth_headers, as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("ok")
      expect(body["audit_event_id"]).to be_present
      expect(body["rotated_at"]).to be_present

      admin.reload
      expect(admin.authenticate("Brand-New-Password-99")).to be_truthy
      expect(admin.must_reset_password).to eq(true)
    end

    it "writes an audit event tagged source: api with the actor token id" do
      post path, params: { password: "Brand-New-Password-99" }, headers: auth_headers, as: :json
      audit = AuditEvent.where(action: "admin_credential_rotated").last
      expect(audit.metadata["source"]).to eq("api")
      expect(audit.metadata["actor_token_id"]).to eq(lambda_token.id)
    end

    it "is idempotent — second call with the same password returns 200/unchanged" do
      post path, params: { password: "Brand-New-Password-99" }, headers: auth_headers, as: :json
      first_changed_at = admin.reload.password_changed_at

      post path, params: { password: "Brand-New-Password-99" }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["status"]).to eq("unchanged")
      expect(admin.reload.password_changed_at).to be_within(0.001).of(first_changed_at)
    end

    it "returns 422 when the password param is missing" do
      post path, params: {}, headers: auth_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 401 without a Bearer token" do
      post path, params: { password: "x" }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns 403 when the token lacks admin.rotate_credentials permission" do
      service_user_role.role.update!(permissions: {})
      post path, params: { password: "Brand-New-Password-99" }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 503 when SPARC_ADMIN_REFRESH_ENABLED is not set" do
      ENV.delete("SPARC_ADMIN_REFRESH_ENABLED")
      post path, params: { password: "Brand-New-Password-99" }, headers: auth_headers, as: :json
      expect(response).to have_http_status(:service_unavailable)
      expect(JSON.parse(response.body)["error"]).to match(/disabled/i)
    end

    it "filters the password out of the Rails parameter logger" do
      filters = Rails.application.config.filter_parameters
      filtered_params = ActiveSupport::ParameterFilter.new(filters)
                                                       .filter("password" => "Brand-New-Password-99")
      expect(filtered_params["password"]).to eq("[FILTERED]")
    end
  end
end
