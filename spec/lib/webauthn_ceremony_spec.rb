# frozen_string_literal: true

require "rails_helper"
require "webauthn/fake_client"

# Proves the server-side WebAuthn ceremony (#779) end to end with no hardware,
# using WebAuthn::FakeClient (ships with the gem). This is the deterministic test
# layer the registration/authentication controllers build on, and it exercises
# BOTH directions — a genuine credential/assertion verifies, a tampered one is
# rejected (per the both-directions security-test standard, #783).
RSpec.describe "WebAuthn ceremony", type: :model do
  let(:origin) { WebAuthn.configuration.allowed_origins.first }
  let(:fake_authenticator) { WebAuthn::FakeClient.new(origin, encoding: :base64url) }
  let(:user) { create(:user) }

  # Run the registration ceremony with the fake authenticator; return the stored
  # WebauthnCredential.
  def register!
    options = WebAuthn::Credential.options_for_create(
      user: { id: user.webauthn_handle, name: user.email },
      authenticator_selection: { user_verification: "required", resident_key: "preferred" }
    )
    raw = fake_authenticator.create(challenge: options.challenge)
    credential = WebAuthn::Credential.from_create(raw)
    credential.verify(options.challenge)

    user.webauthn_credentials.create!(
      external_id: credential.id,
      public_key: credential.public_key,
      sign_count: credential.sign_count,
      nickname: "Test key"
    )
  end

  describe "registration" do
    it "verifies a real attestation and stores the credential" do
      cred = register!
      expect(cred).to be_persisted
      expect(cred.external_id).to be_present
      expect(user.reload.webauthn_registered?).to be(true)
    end

    it "rejects an attestation verified against the wrong challenge (fail-closed)" do
      options = WebAuthn::Credential.options_for_create(
        user: { id: user.webauthn_handle, name: user.email }
      )
      raw = fake_authenticator.create(challenge: options.challenge)
      credential = WebAuthn::Credential.from_create(raw)

      expect {
        credential.verify(WebAuthn::Credential.options_for_create(user: { id: user.webauthn_handle, name: user.email }).challenge)
      }.to raise_error(WebAuthn::Error)
    end
  end

  describe "authentication" do
    before { register! }

    it "verifies a real assertion against the stored public key" do
      options = WebAuthn::Credential.options_for_get(
        allow: user.webauthn_credentials.pluck(:external_id),
        user_verification: "required"
      )
      raw = fake_authenticator.get(challenge: options.challenge)
      assertion = WebAuthn::Credential.from_get(raw)

      stored = user.webauthn_credentials.find_by(external_id: assertion.id)
      expect(stored).to be_present
      expect {
        assertion.verify(options.challenge, public_key: stored.public_key, sign_count: stored.sign_count)
      }.not_to raise_error
    end

    it "rejects an assertion verified against the wrong challenge (fail-closed)" do
      options = WebAuthn::Credential.options_for_get(allow: user.webauthn_credentials.pluck(:external_id))
      raw = fake_authenticator.get(challenge: options.challenge)
      assertion = WebAuthn::Credential.from_get(raw)
      stored = user.webauthn_credentials.find_by(external_id: assertion.id)

      wrong_challenge = WebAuthn::Credential.options_for_get(allow: []).challenge
      expect {
        assertion.verify(wrong_challenge, public_key: stored.public_key, sign_count: stored.sign_count)
      }.to raise_error(WebAuthn::Error)
    end
  end

  describe WebauthnCredential do
    it "labels a nameless key and advances the sign counter on use" do
      cred = register!
      cred.update!(nickname: nil)
      expect(cred.label).to eq("Security key")
      cred.record_use!(5)
      expect(cred.reload.sign_count).to eq(5)
      expect(cred.last_used_at).to be_present
    end
  end
end
