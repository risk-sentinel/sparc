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
class ApiToken < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true

  scope :active, -> {
    where("expires_at IS NULL OR expires_at > ?", Time.current)
  }

  attr_accessor :plaintext_token

  # Generate a new API token with a secure random value.
  # Returns the token record with `plaintext_token` set (available only now).
  def self.generate!(user:, name:, expires_at: nil, scopes: {})
    plaintext = "sparc_#{SecureRandom.hex(32)}"
    token = create!(
      user: user,
      name: name,
      token_digest: Digest::SHA256.hexdigest(plaintext),
      expires_at: expires_at,
      scopes: scopes
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
end
