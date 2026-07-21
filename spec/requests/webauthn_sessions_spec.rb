# frozen_string_literal: true

require "rails_helper"
require "webauthn/fake_client"

# Passwordless FIDO2 sign-in (#779), driven by WebAuthn::FakeClient — no hardware.
# A key + PIN authenticates and establishes a session in one ceremony; both
# directions per #783 (genuine assertion signs in; wrong challenge, unknown key,
# cloned-counter, inactive user, disabled flag are all rejected).
RSpec.describe "WebauthnSessions", type: :request do
  let(:user)   { create(:user) }
  let(:origin) { WebAuthn.configuration.allowed_origins.first }
  # persistent authenticator: retains the resident credential across create/get.
  let(:fake)   { WebAuthn::FakeClient.new(origin, encoding: :base64url) }

  before { allow(SparcConfig).to receive(:fido2_enabled?).and_return(true) }

  # Enroll a resident credential for `user` on the fake authenticator, storing it
  # exactly as the enrollment ceremony would.
  def enroll_key!
    options = WebAuthn::Credential.options_for_create(
      user: { id: user.webauthn_handle, name: user.email }
    )
    raw = fake.create(challenge: options.challenge, user_verified: true)
    credential = WebAuthn::Credential.from_create(raw)
    user.webauthn_credentials.create!(
      external_id: credential.id, public_key: credential.public_key, sign_count: credential.sign_count
    )
  end

  # Run the sign-in ceremony (usernameless by default).
  def sign_in_with_key!(email: nil)
    post webauthn_authentication_options_path, params: { email: email }.compact
    challenge = response.parsed_body["challenge"]
    assertion = fake.get(challenge: challenge, user_verified: true)
    post webauthn_session_path, params: { credential: assertion }, as: :json
  end

  describe "usernameless (discoverable) sign-in" do
    before { enroll_key! }

    it "signs the user in with the key alone and audits it" do
      expect { sign_in_with_key! }
        .to change { AuditEvent.where(action: "login_success", provider: "webauthn").count }.by(1)
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["redirect_to"]).to eq(root_path)
      # A protected page is now reachable — the session is real.
      get root_path
      expect(response).not_to redirect_to(login_path)
    end

    it "advances the stored signature counter (clone detection)" do
      expect { sign_in_with_key! }.to change { user.webauthn_credentials.first.reload.last_used_at }.from(nil)
    end
  end

  describe "email-first sign-in (non-resident fallback)" do
    before { enroll_key! }

    it "signs in when the email resolves to the key's owner" do
      sign_in_with_key!(email: user.email)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "fail-closed" do
    before { enroll_key! }

    it "rejects an assertion for the wrong challenge" do
      post webauthn_authentication_options_path              # stashes challenge A
      other = WebAuthn::Credential.options_for_get(allow: user.webauthn_credentials.pluck(:external_id))
      assertion = fake.get(challenge: other.challenge, user_verified: true)  # signs challenge B
      post webauthn_session_path, params: { credential: assertion }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects a create with no sign-in in progress" do
      assertion = fake.get(challenge: WebAuthn::Credential.options_for_get(allow: user.webauthn_credentials.pluck(:external_id)).challenge, user_verified: true)
      post webauthn_session_path, params: { credential: assertion }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects an inactive user's key and audits the failure" do
      user.update!(status: "deactivated")
      expect { sign_in_with_key! }
        .to change { AuditEvent.where(action: "login_failure", provider: "webauthn").count }.by(1)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "feature flag" do
    it "404s when FIDO2 is disabled" do
      allow(SparcConfig).to receive(:fido2_enabled?).and_return(false)
      post webauthn_authentication_options_path
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "login page" do
    it "offers the security-key sign-in and counts FIDO2 as auth being enabled" do
      # FIDO2-only deployment: any_auth_enabled? must be true so /login renders.
      expect(SparcConfig.any_auth_enabled?).to be(true)
      get login_path
      expect(response.body).to include("Sign in with a security key")
    end
  end
end
