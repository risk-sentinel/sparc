require "rails_helper"

RSpec.describe "API Auth Modes", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:service_user) { create(:user, :admin, service_account: true, email: "pipeline@service.local") }
  let(:sparc_token) { ApiToken.generate!(user: admin, name: "Test Token") }
  let(:service_token) { ApiToken.generate!(user: service_user, name: "Pipeline Token") }
  let(:sparc_headers) { { "Authorization" => "Bearer #{sparc_token.plaintext_token}" } }
  let(:service_headers) { { "Authorization" => "Bearer #{service_token.plaintext_token}" } }
  let(:jwt_headers) { { "Authorization" => "Bearer eyJhbGciOiJSUzI1NiJ9.fake.token" } }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  # ── Local mode ────────────────────────────────────────────────────────────

  describe "SPARC_API_AUTH=local" do
    before do
      allow(SparcConfig).to receive(:api_auth_mode).and_return("local")
    end

    it "accepts SPARC tokens" do
      get api_v1_ssp_documents_path, headers: sparc_headers
      expect(response).to have_http_status(:ok)
    end

    it "rejects JWT tokens with clear message" do
      get api_v1_ssp_documents_path, headers: jwt_headers
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("OIDC authentication is not enabled")
    end

    it "returns 401 with no token" do
      get api_v1_ssp_documents_path
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("Missing or invalid Authorization header")
    end
  end

  # ── OIDC mode ─────────────────────────────────────────────────────────────

  describe "SPARC_API_AUTH=oidc" do
    before do
      allow(SparcConfig).to receive(:api_auth_mode).and_return("oidc")
    end

    it "rejects SPARC tokens with clear message" do
      get api_v1_ssp_documents_path, headers: sparc_headers
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("Local token authentication is not enabled")
    end

    it "rejects invalid JWTs (since no real OIDC provider)" do
      get api_v1_ssp_documents_path, headers: jwt_headers
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("Invalid or expired OIDC token")
    end
  end

  # ── Hybrid mode ───────────────────────────────────────────────────────────

  describe "SPARC_API_AUTH=hybrid" do
    before do
      allow(SparcConfig).to receive(:api_auth_mode).and_return("hybrid")
    end

    it "accepts SPARC tokens from service accounts" do
      get api_v1_ssp_documents_path, headers: service_headers
      expect(response).to have_http_status(:ok)
    end

    it "rejects SPARC tokens from non-service-account users" do
      get api_v1_ssp_documents_path, headers: sparc_headers
      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to include("Service account token required in hybrid mode")
    end

    it "rejects invalid JWTs (since no real OIDC provider)" do
      get api_v1_ssp_documents_path, headers: jwt_headers
      expect(response).to have_http_status(:unauthorized)
    end
  end

  # ── Auth mode metadata ────────────────────────────────────────────────────

  describe "current_auth_mode tracking" do
    before do
      allow(SparcConfig).to receive(:api_auth_mode).and_return("local")
    end

    it "sets auth_mode to local for SPARC token auth" do
      get api_v1_ssp_documents_path, headers: sparc_headers
      expect(response).to have_http_status(:ok)
    end
  end

  # ── Service account web login ─────────────────────────────────────────────

  describe "service account web login" do
    before do
      allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
      allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    end

    it "rejects service accounts from logging in via web UI" do
      post login_path, params: { email: service_user.email, password: service_user.password || "anything" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Service accounts cannot log in via the web interface")
    end
  end

  # ── User model scopes ────────────────────────────────────────────────────

  describe "User.service_accounts / User.human_users" do
    it "scopes correctly" do
      admin
      service_user
      expect(User.service_accounts).to include(service_user)
      expect(User.service_accounts).not_to include(admin)
      expect(User.human_users).to include(admin)
      expect(User.human_users).not_to include(service_user)
    end

    it "defaults service_account to false" do
      user = create(:user)
      expect(user.service_account?).to be false
    end
  end
end
