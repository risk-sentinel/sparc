# A configured remote SPARC instance from which this instance pulls
# authoritative back-matter resources, or to which this instance exports
# bundles for consumption.
#
# Trust model:
#   - Outbound calls authenticate to the peer with `service_token` (Bearer)
#   - Inbound bundles are HMAC-signed using `signing_secret`; the same
#     secret verifies our outbound bundles on the peer side. The shared
#     `signing_secret` is exchanged out of band when the peer is configured.
#
# All stored credentials are encrypted at rest via
# `ActiveSupport::MessageEncryptor`, keyed by SparcKeyDerivation. The
# master secret (SPARC_HASH) is provisioned by sparc-iac into the
# instance's secrets pipeline; locally we fall back to secret_key_base.
#
# NIST AC-4 / SC-8 / SC-12 / SC-13: cross-instance flow over signed,
#                                   verified channels with encrypted creds.
# NIST IA-5: encrypt-then-MAC token + secret storage.
class FederationPeer < ApplicationRecord
  TOKEN_KEY_PURPOSE  = "federation_peer_service_token"
  SECRET_KEY_PURPOSE = "federation_peer_signing_secret"

  validates :name, presence: true, uniqueness: true
  validates :base_url, presence: true,
            format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]),
                      message: "must be a valid http(s) URL" }

  scope :enabled,  -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }

  def service_token
    decrypt(encrypted_service_token, self.class.token_encryptor)
  end

  def service_token=(value)
    self.encrypted_service_token = encrypt(value, self.class.token_encryptor)
  end

  def signing_secret
    decrypt(encrypted_signing_secret, self.class.secret_encryptor)
  end

  def signing_secret=(value)
    self.encrypted_signing_secret = encrypt(value, self.class.secret_encryptor)
  end

  def self.token_encryptor
    @token_encryptor ||= build_encryptor(TOKEN_KEY_PURPOSE)
  end

  def self.secret_encryptor
    @secret_encryptor ||= build_encryptor(SECRET_KEY_PURPOSE)
  end

  def self.reset_encryptors!
    @token_encryptor = nil
    @secret_encryptor = nil
  end

  def self.build_encryptor(purpose)
    key = SparcKeyDerivation.derive(purpose,
                                    length: ActiveSupport::MessageEncryptor.key_len)
    ActiveSupport::MessageEncryptor.new(key)
  end

  # Build an encryptor keyed by an explicit master rather than the
  # configured one. Used by FederationPeerReencryptionService (#419) to
  # decrypt rows still under a previous master before re-encrypting them
  # under the current one.
  def self.build_encryptor_with_master(master, purpose)
    key = SparcKeyDerivation.derive_from(
      master, purpose, length: ActiveSupport::MessageEncryptor.key_len
    )
    ActiveSupport::MessageEncryptor.new(key)
  end

  private

  def decrypt(ciphertext, encryptor)
    return nil if ciphertext.blank?

    encryptor.decrypt_and_verify(ciphertext)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage,
         ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def encrypt(value, encryptor)
    value.present? ? encryptor.encrypt_and_sign(value.to_s) : nil
  end
end
