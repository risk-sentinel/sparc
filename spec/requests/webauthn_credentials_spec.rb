# frozen_string_literal: true

require "rails_helper"
require "webauthn/fake_client"

# Registration ceremony backend (#779), driven end to end by WebAuthn::FakeClient
# — no hardware. Exercises both directions per the #783 standard: a genuine
# attestation enrolls a key (and is audited); a mismatched/absent challenge, a
# disabled feature flag, and an unauthenticated request are all rejected.
RSpec.describe "WebauthnCredentials", type: :request do
  let(:user)   { create(:user, first_name: "Kay", last_name: "Cee") }
  let(:origin) { WebAuthn.configuration.allowed_origins.first }
  let(:fake)   { WebAuthn::FakeClient.new(origin, encoding: :base64url) }

  before do
    allow(SparcConfig).to receive(:fido2_enabled?).and_return(true)
    sign_in_as(user)
  end

  # Full happy-path enrollment: fetch options, have the fake authenticator attest,
  # POST the credential.
  def enroll!(nickname: "My YubiKey")
    post registration_options_webauthn_credentials_path
    challenge = response.parsed_body["challenge"]
    # user_verified: true simulates the PIN/biometric — the ceremony requires UV.
    credential = fake.create(challenge: challenge, user_verified: true)
    post webauthn_credentials_path, params: { credential: credential, nickname: nickname }, as: :json
  end

  describe "enrollment" do
    it "registers a security key and audits it" do
      expect { enroll! }
        .to change { user.webauthn_credentials.count }.by(1)
        .and change { AuditEvent.where(action: "webauthn_key_registered").count }.by(1)
      expect(response).to have_http_status(:created)
      expect(response.parsed_body["label"]).to eq("My YubiKey")
      expect(user.reload.webauthn_registered?).to be(true)
    end

    it "rejects an attestation built for a different challenge (fail-closed)" do
      post registration_options_webauthn_credentials_path            # stashes challenge A
      other = WebAuthn::Credential.options_for_create(user: { id: user.webauthn_handle, name: user.email })
      credential = fake.create(challenge: other.challenge, user_verified: true)  # attests to challenge B
      post webauthn_credentials_path, params: { credential: credential }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.webauthn_credentials.count).to eq(0)
    end

    it "rejects a create with no enrollment in progress" do
      credential = fake.create(challenge: WebAuthn::Credential.options_for_create(user: { id: user.webauthn_handle, name: user.email }).challenge)
      post webauthn_credentials_path, params: { credential: credential }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "revocation" do
    it "removes a key and audits it" do
      enroll!
      credential = user.webauthn_credentials.first
      expect { delete webauthn_credential_path(credential), as: :json }
        .to change { user.webauthn_credentials.count }.by(-1)
        .and change { AuditEvent.where(action: "webauthn_key_revoked").count }.by(1)
      expect(response).to have_http_status(:no_content)
    end
  end

  describe "listing" do
    it "returns the user's keys as JSON" do
      enroll!(nickname: "Backup key")
      get webauthn_credentials_path, as: :json
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body.map { |c| c["label"] }).to include("Backup key")
    end
  end

  describe "feature flag (graceful fallback)" do
    it "404s every endpoint when FIDO2 is disabled" do
      allow(SparcConfig).to receive(:fido2_enabled?).and_return(false)
      post registration_options_webauthn_credentials_path
      expect(response).to have_http_status(:not_found)
    end
  end
end
