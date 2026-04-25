# A configured remote SPARC instance from which this instance pulls
# authoritative back-matter resources. Trust model reuses the existing
# OSCAL artifact signing key infrastructure: bundles arrive signed by the
# peer and are verified against its registered public key (delivered
# out-of-band when the peer is configured).
#
# Service tokens are encrypted at rest using a per-instance key derived
# from `Rails.application.secret_key_base` via `ActiveSupport::KeyGenerator`.
# Plaintext is only available in-process during outbound requests.
#
# NIST AC-4 / SC-8 / SC-12: cross-instance information flow over signed,
#                           verified channels with encrypted credentials.
# NIST IA-5: token storage uses authenticated encryption (encrypt-then-MAC
#            via ActiveSupport::MessageEncryptor).
class FederationPeer < ApplicationRecord
  TOKEN_KEY_PURPOSE = "federation_peer_service_token"

  validates :name, presence: true, uniqueness: true
  validates :base_url, presence: true,
            format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]),
                      message: "must be a valid http(s) URL" }

  scope :enabled,  -> { where(enabled: true) }
  scope :disabled, -> { where(enabled: false) }

  def service_token
    return nil if encrypted_service_token.blank?

    self.class.token_encryptor.decrypt_and_verify(encrypted_service_token)
  rescue ActiveSupport::MessageEncryptor::InvalidMessage,
         ActiveSupport::MessageVerifier::InvalidSignature
    nil
  end

  def service_token=(value)
    self.encrypted_service_token =
      value.present? ? self.class.token_encryptor.encrypt_and_sign(value.to_s) : nil
  end

  def self.token_encryptor
    @token_encryptor ||= begin
      key = ActiveSupport::KeyGenerator
              .new(Rails.application.secret_key_base, hash_digest_class: OpenSSL::Digest::SHA256)
              .generate_key(TOKEN_KEY_PURPOSE, ActiveSupport::MessageEncryptor.key_len)
      ActiveSupport::MessageEncryptor.new(key)
    end
  end
end
