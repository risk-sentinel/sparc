# frozen_string_literal: true

# A FIDO2/WebAuthn security key registered to a User (#779). A user may register
# several; each is usable passwordless (resident credential + PIN) or as a second
# factor. SPARC stores only the public half: the credential id, the COSE public
# key, and the signature counter — the private key never leaves the authenticator.
#
# NIST 800-53: IA-2(1)/(2) MFA, IA-2(8) replay-resistant (sign-count regression
# detects a cloned key), IA-5 authenticator management.
class WebauthnCredential < ApplicationRecord
  belongs_to :user

  # external_id is the base64url-encoded WebAuthn credential id; unique globally.
  validates :external_id, presence: true, uniqueness: true
  validates :public_key, presence: true
  validates :sign_count, numericality: { greater_than_or_equal_to: 0 }

  scope :by_recent_use, -> { order(Arel.sql("last_used_at DESC NULLS LAST"), created_at: :desc) }

  # A friendly label for the key management UI; falls back to a generic name.
  def label
    nickname.presence || "Security key"
  end

  # Record a successful authentication: advance the stored counter and stamp use.
  # A verified assertion's sign_count must be strictly greater than the stored one
  # (0/0 is allowed for authenticators that don't implement a counter).
  def record_use!(new_sign_count)
    update!(sign_count: new_sign_count, last_used_at: Time.current)
  end
end
