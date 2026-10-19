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
#   IA-5(1)/IA-5 lifetime (#1176): a service account's token must expire,
#     within SPARC_API_TOKEN_MAX_DAYS; renew! overlaps for a grace window
#   AC-3 Access Enforcement (endpoint scoping via allowed_endpoints, read
#     through ApiEndpointCatalog — #1176)
#   AC-17 Remote Access (CIDR allowlist via allowed_cidrs)
#   SC-13 Cryptographic Protection (SecureRandom.hex, SHA-256)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class ApiToken < ApplicationRecord
  belongs_to :user
  belongs_to :created_by, class_name: "User", optional: true

  # How close to expiry a token is flagged on the screens and in the API. The
  # same 14 days the owner warning e-mail uses (ServiceAccountNotificationJob).
  EXPIRING_SOON_DAYS = 14

  # A service account with no expiry chosen anywhere gets this lifetime: the
  # default every service-account path has used since #1013.
  DEFAULT_SERVICE_ACCOUNT_DAYS = 90

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validate :endpoint_entries_known, if: :will_save_change_to_allowed_endpoints?, unless: :limits_carried_over
  validate :service_account_lifetime, on: :create

  before_validation { self.allowed_endpoints = ApiEndpointCatalog.normalize(allowed_endpoints) }

  scope :active, -> {
    where("expires_at IS NULL OR expires_at > ?", Time.current)
  }

  attr_accessor :plaintext_token

  # Set on a renewal or reissue: its limits are copied, not submitted, so an
  # old path pattern that no longer matches a route does not block it.
  attr_accessor :limits_carried_over

  # Generate a new API token with a secure random value.
  # Returns the token record with `plaintext_token` set (available only now).
  # Service account tokens use `sparc_sa_` prefix for identification (IA-4).
  def self.generate!(user:, name:, expires_at: nil, scopes: {}, created_by: nil, allowed_endpoints: [], allowed_cidrs: [],
                     limits_carried_over: false)
    prefix = user.service_account? ? "sparc_sa_" : "sparc_"
    plaintext = "#{prefix}#{SecureRandom.hex(32)}"
    token = create!(
      limits_carried_over: limits_carried_over,
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

  # #1176 — a service account's "Regenerate token" (web and API): revoke every
  # token it holds and issue one. Limits not given explicitly are carried over
  # from its newest token, preferring one still active, so rotating never
  # widens the credential. Before #1176 the web button sent no limits at all
  # and the replacement could reach every endpoint from any address.
  def self.regenerate_for!(account, by:, expires_in_days: nil, allowed_endpoints: nil, allowed_cidrs: nil)
    transaction do
      template = account.api_tokens.active.order(created_at: :desc).first ||
                 account.api_tokens.order(created_at: :desc).first
      days = expires_in_days.presence&.to_i
      # A carried-over lifetime may predate the cap; clamp it. An explicit
      # request beyond the cap is left to fail validation, never shortened.
      days ||= [ template&.lifetime_days || DEFAULT_SERVICE_ACCOUNT_DAYS, SparcConfig.api_token_max_days ].min
      endpoints = allowed_endpoints.nil? ? template&.allowed_endpoints : allowed_endpoints
      cidrs = allowed_cidrs.nil? ? template&.allowed_cidrs : allowed_cidrs

      account.api_tokens.destroy_all
      generate!(
        user: account, name: "Regenerated token", created_by: by,
        expires_at: days.positive? ? days.days.from_now : nil,
        allowed_endpoints: endpoints || [], allowed_cidrs: cidrs || [],
        limits_carried_over: allowed_endpoints.nil?
      )
    end
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

  def never_expires? = expires_at.nil?

  def expiring_soon?
    expires_at.present? && !expired? && expires_at <= EXPIRING_SOON_DAYS.days.from_now
  end

  # Whole days the token was issued for, carried to its renewal or reissue.
  # A token with no expiry has none; a service account's replacement then
  # takes the default, since it may not be issued without one.
  def lifetime_days
    return nil if expires_at.nil?

    [ ((expires_at - created_at) / 1.day).round, 1 ].max
  end

  # #1176 — RENEW: a new token with the same name, endpoints, CIDRs and
  # lifetime. This one keeps working for SPARC_API_TOKEN_RENEWAL_GRACE_DAYS
  # (never longer than it already would), so automation can switch over
  # without an outage. Returns the new token, plaintext set.
  def renew!(by:)
    transaction do
      replacement = issue_replacement(by: by)
      grace_end = SparcConfig.api_token_renewal_grace_days.days.from_now
      update!(expires_at: [ expires_at, grace_end ].compact.min)
      replacement
    end
  end

  # #1176 — REISSUE: revoke this token at once and issue a replacement with
  # the same limits. Before #1176 the admin Regenerate button issued its
  # replacement with NO endpoint or CIDR limits, widening the credential.
  def reissue!(by:)
    transaction do
      replacement = issue_replacement(by: by)
      destroy!
      replacement
    end
  end

  def endpoint_summary = ApiEndpointCatalog.describe(allowed_endpoints)

  # AC-3: Check if the request is allowed by this token's endpoint limits.
  # Empty allowed_endpoints means all endpoints are permitted. The rules live
  # in ApiEndpointCatalog, the one definition the forms and the API also use.
  def endpoint_allowed?(path, verb: "GET", route_key: nil)
    ApiEndpointCatalog.permits?(allowed_endpoints, path: path, verb: verb, route_key: route_key)
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

  private

  def issue_replacement(by:)
    days = lifetime_days || (user.service_account? ? DEFAULT_SERVICE_ACCOUNT_DAYS : nil)
    if days && user.service_account?
      days = [ days, SparcConfig.api_token_max_days ].min
    end
    self.class.generate!(
      user: user, name: name, created_by: by,
      expires_at: days&.days&.from_now,
      scopes: scopes, allowed_endpoints: allowed_endpoints, allowed_cidrs: allowed_cidrs,
      limits_carried_over: true
    )
  end

  def endpoint_entries_known
    ApiEndpointCatalog.errors_for(allowed_endpoints).each do |message|
      errors.add(:allowed_endpoints, message)
    end
  end

  # #1176 — a service account's credential must expire, and within the cap.
  # Checked here, not in a controller, so no path can skip it: the account
  # form, the admin user page, /api/v1/users/:id/api_tokens and
  # /api/v1/service_accounts all create through this model. A person's token
  # may still be set to never expire (owner, 2026-10-18).
  def service_account_lifetime
    return unless user&.service_account?

    max = SparcConfig.api_token_max_days
    if expires_at.nil?
      errors.add(:expires_at, "is required for a service account's token (at most #{max} days)")
    elsif expires_at > (max.days + 1.minute).from_now
      errors.add(:expires_at, "may be at most #{max} days away for a service account's token (SPARC_API_TOKEN_MAX_DAYS)")
    end
  end
end
