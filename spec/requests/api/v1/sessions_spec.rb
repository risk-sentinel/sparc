# frozen_string_literal: true

require "rails_helper"

# #573 — Bearer-token → Rails session cookie bridge.
RSpec.describe "Api::V1::Sessions", type: :request do
  let(:admin)           { create(:user, :admin) }
  let(:owner)           { create(:user, :admin) }
  let(:admin_sa)        { create(:user, :admin, service_account: true, owner: owner, email: "sa@example.com") }
  let(:api_token)       { ApiToken.generate!(user: admin,    name: "Test bridge") }
  let(:sa_token)        { ApiToken.generate!(user: admin_sa, name: "Test SA bridge") }
  let(:auth_headers)    { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }
  let(:sa_auth_headers) { { "Authorization" => "Bearer #{sa_token.plaintext_token}" } }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
  end

  describe "POST /api/v1/sessions/from_token" do
    it "returns 204 + sets a session cookie for a valid token" do
      post api_v1_sessions_from_token_path, headers: auth_headers
      expect(response).to have_http_status(:no_content)
      expect(response.headers["Set-Cookie"]).to be_present
      expect(response.headers["Set-Cookie"]).to match(/session=/i)
    end

    it "bridges a service-account token (the primary Playwright use case)" do
      post api_v1_sessions_from_token_path, headers: sa_auth_headers
      expect(response).to have_http_status(:no_content)
      expect(response.headers["Set-Cookie"]).to match(/session=/i)
    end

    it "emits an api_session_bridged audit event on success" do
      expect {
        post api_v1_sessions_from_token_path, headers: auth_headers
      }.to change { AuditEvent.where(action: "api_session_bridged").count }.by(1)

      event = AuditEvent.where(action: "api_session_bridged").last
      expect(event.user_id).to eq(admin.id)
      expect(event.metadata["is_service_account"]).to be(false)
    end

    it "audit event records is_service_account: true for SA bridges" do
      post api_v1_sessions_from_token_path, headers: sa_auth_headers
      event = AuditEvent.where(action: "api_session_bridged").last
      expect(event.metadata["is_service_account"]).to be(true)
    end

    it "returns 401 + emits api_session_bridge_failed when the Authorization header is missing" do
      expect {
        post api_v1_sessions_from_token_path
      }.to change { AuditEvent.where(action: "api_session_bridge_failed").count }.by(1)

      expect(response).to have_http_status(:unauthorized)
      expect(response.headers["Set-Cookie"].to_s).not_to match(/session=[A-Za-z0-9%]/i) if response.headers["Set-Cookie"]

      failure = AuditEvent.where(action: "api_session_bridge_failed").last
      expect(failure.metadata["reason"]).to eq("missing_token")
    end

    it "returns 401 + emits api_session_bridge_failed when the token is invalid" do
      expect {
        post api_v1_sessions_from_token_path,
             headers: { "Authorization" => "Bearer sparc_invalid_token_value" }
      }.to change { AuditEvent.where(action: "api_session_bridge_failed").count }.by(1)

      expect(response).to have_http_status(:unauthorized)
      failure = AuditEvent.where(action: "api_session_bridge_failed").last
      expect(failure.metadata["reason"]).to eq("invalid_token")
    end

    it "returns 401 when the token has been revoked, with no Set-Cookie" do
      api_token.update!(revoked_at: Time.current) if api_token.respond_to?(:revoked_at=)
      api_token.destroy

      post api_v1_sessions_from_token_path, headers: auth_headers
      expect(response).to have_http_status(:unauthorized)
      cookie = response.headers["Set-Cookie"].to_s
      expect(cookie).not_to match(/session=[A-Za-z0-9%]/)
    end

    it "produces a session that authenticates subsequent web requests" do
      # First: bridge.
      post api_v1_sessions_from_token_path, headers: auth_headers
      expect(response).to have_http_status(:no_content)

      # Capture the cookie Rack handed us and re-attach to a follow-up
      # web request. The follow-up should NOT redirect to /login.
      bridged_cookie = response.headers["Set-Cookie"].to_s.split(";").first.to_s.strip
      get root_path, headers: { "Cookie" => bridged_cookie }
      expect(response).not_to redirect_to(login_path)
      expect(response).to have_http_status(:ok).or have_http_status(:found)
    end

    it "lists itself in /api/v1/available discovery output" do
      get api_v1_available_path, headers: auth_headers
      data = JSON.parse(response.body)
      paths = data["endpoints"].map { |e| e["path"] }
      expect(paths).to include("/api/v1/sessions/from_token")
    end
  end
end
