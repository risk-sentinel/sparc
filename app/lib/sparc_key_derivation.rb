# Derives purpose-specific cryptographic keys from a single instance master
# secret (`SPARC_HASH`). All SPARC subsystems that need a stable, instance-
# scoped symmetric key — at-rest encryption of stored credentials, HMAC
# signing of federation bundles, etc. — should derive their key here rather
# than reading SPARC_HASH directly. That keeps the master secret in one
# narrow place and keeps each call-site bound to its purpose.
#
# In production, SPARC_HASH is provisioned by the IaC layer (sparc-iac)
# into AWS Secrets Manager and exposed to the ECS task as an env var.
# In dev/test, when SPARC_HASH is unset we fall back to Rails'
# `secret_key_base` so local workflows do not require extra setup.
#
# Each derived key is bound to a string `purpose` plus a domain separator,
# so two purposes can never collide even if the master secret is identical.
#
# NIST 800-53:
#   SC-12  Cryptographic Key Establishment & Management
#   SC-13  Cryptographic Protection (HKDF via ActiveSupport::KeyGenerator)
#   IA-5   Authenticator Management (master secret rotated externally)
module SparcKeyDerivation
  PURPOSE_PREFIX = "sparc:v1:"
  DEFAULT_KEY_LEN = 32

  module_function

  # Derive a key for the given purpose. `length` defaults to 32 bytes
  # (256 bits), suitable for HMAC-SHA256 and AES-256 keys.
  def derive(purpose, length: DEFAULT_KEY_LEN)
    raise ArgumentError, "purpose is required" if purpose.to_s.strip.empty?

    generator.generate_key("#{PURPOSE_PREFIX}#{purpose}", length)
  end

  # Returns true when SPARC_HASH is provisioned. Useful for surfacing a
  # warning in non-dev environments where the fallback path is unsafe.
  def master_secret_configured?
    ENV["SPARC_HASH"].to_s.length >= 32
  end

  def reset!
    @generator = nil
  end

  def generator
    @generator ||= ActiveSupport::KeyGenerator.new(
      master_secret,
      hash_digest_class: OpenSSL::Digest::SHA256
    )
  end

  def master_secret
    secret = ENV["SPARC_HASH"].to_s
    return secret if secret.length >= 32

    if Rails.env.production?
      Rails.logger.warn(
        "[SparcKeyDerivation] SPARC_HASH is unset or too short in production — " \
        "falling back to secret_key_base. Provision SPARC_HASH via the " \
        "sparc-iac secrets pipeline."
      )
    end
    Rails.application.secret_key_base
  end
end
