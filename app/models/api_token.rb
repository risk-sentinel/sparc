# API token for Bearer token authentication.
#
# Tokens are generated with a cryptographically secure random value.
# Only the SHA-256 digest is stored in the database. The plaintext
# token is available only at creation time via `plaintext_token`.
#
# Usage:
#   token = ApiToken.generate!(user: current_user, name: "CI Pipeline")
#   token.plaintext_token  # => "sparc_abc123..." (show once to user)
#
#   # Later, authenticate:
#   api_token = ApiToken.authenticate("sparc_abc123...")
#   api_token.user  # => User record
#
# NIST 800-53 Controls:
#   IA-5 Authenticator Management (SHA-256 digest, no plaintext storage)
#   AC-3 Access Enforcement (endpoint scoping via allowed_endpoints)
#   AC-17 Remote Access (CIDR allowlist via allowed_cidrs)
#   SC-13 Cryptographic Protection (SecureRandom.hex, SHA-256)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class ApiToken < ApplicationRecord
  belongs_to :user
  belongs_to :created_by, class_name: "User", optional: true

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true

  scope :active, -> {
    where("expires_at IS NULL OR expires_at > ?", Time.current)
  }

  attr_accessor :plaintext_token

  # Generate a new API token with a secure random value.
  # Returns the token record with `plaintext_token` set (available only now).
  # Service account tokens use `sparc_sa_` prefix for identification (IA-4).
  def self.generate!(user:, name:, expires_at: nil, scopes: {}, created_by: nil, allowed_endpoints: [], allowed_cidrs: [])
    prefix = user.service_account? ? "sparc_sa_" : "sparc_"
    plaintext = "#{prefix}#{SecureRandom.hex(32)}"
    token = create!(
      user: user,
      name: name,
      token_digest: Digest::SHA256.hexdigest(plaintext),
      expires_at: expires_at,
      scopes: scopes,
      created_by: created_by,
      allowed_endpoints: allowed_endpoints || [],
      allowed_cidrs: allowed_cidrs || []
    )
    token.plaintext_token = plaintext
    token
  end

  # Authenticate a plaintext token string.
  # Returns the ApiToken record if valid and not expired, nil otherwise.
  def self.authenticate(plaintext)
    return nil if plaintext.blank?

    digest = Digest::SHA256.hexdigest(plaintext)
    active.includes(:user).find_by(token_digest: digest)
  end

  # Record usage timestamp and IP.
  def touch_usage!(ip: nil)
    update_columns(last_used_at: Time.current, last_used_ip: ip)
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  # AC-3: Check if the requested endpoint is allowed by this token.
  # Empty allowed_endpoints means all endpoints are permitted.
  def endpoint_allowed?(path)
    return true if allowed_endpoints.blank?

    allowed_endpoints.any? do |pattern|
      if pattern.end_with?("*")
        path.start_with?(pattern.chomp("*"))
      else
        path == pattern
      end
    end
  end

  # AC-17: Check if the request IP is within allowed CIDR ranges.
  # Empty allowed_cidrs means all IPs are permitted.
  def cidr_allowed?(ip)
    return true if allowed_cidrs.blank?
    return true if ip.blank?

    request_ip = IPAddr.new(ip)
    allowed_cidrs.any? { |cidr| IPAddr.new(cidr).include?(request_ip) }
  rescue IPAddr::InvalidAddressError
    false
  end
end
