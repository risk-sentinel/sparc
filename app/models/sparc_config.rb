# frozen_string_literal: true

# Centralized configuration module that reads SPARC_* environment variables
# with sensible defaults. Follows MITRE Vulcan's pattern of env-var-driven
# feature toggling — all auth features default to disabled (whitelist approach).
#
# Usage:
#   SparcConfig.app_name          # => "SPARC"
#   SparcConfig.enable_oidc?      # => false (unless SPARC_ENABLE_OIDC=true)
#   SparcConfig.any_auth_enabled? # => true if any login method is enabled
#
# See docs/ENVIRONMENT_VARIABLES.md for the full configuration reference.
module SparcConfig
  VERSION = "3.4.7"

  module_function

  def version = VERSION

  # ── Database ──────────────────────────────────────────────────────────────
  # These are fallbacks when DATABASE_URL is not set. DATABASE_URL always
  # takes priority per Rails convention.

  def db_host     = ENV.fetch("SPARC_DB_HOST", "localhost")
  def db_port     = ENV.fetch("SPARC_DB_PORT", "5432").to_i
  def db_name     = ENV.fetch("SPARC_DB_NAME", "sparc")
  def db_user     = ENV.fetch("SPARC_DB_USER", nil)
  def db_password = ENV.fetch("SPARC_DB_PASSWORD", nil)
  def db_sslmode  = ENV.fetch("SPARC_DB_SSLMODE", "prefer")

  # ── Application ───────────────────────────────────────────────────────────

  def app_url       = ENV.fetch("SPARC_APP_URL", "http://localhost:3000")
  def app_name      = ENV.fetch("SPARC_APP_NAME", "SPARC")
  def contact_email = ENV.fetch("SPARC_CONTACT_EMAIL", nil)
  def welcome_text  = ENV.fetch("SPARC_WELCOME_TEXT", "Welcome to SPARC")

  # ── Authentication Toggles ────────────────────────────────────────────────
  # All default to false — features must be explicitly enabled.

  def enable_local_login?  = ENV.fetch("SPARC_ENABLE_LOCAL_LOGIN", "false") == "true"
  def enable_oidc?         = ENV.fetch("SPARC_ENABLE_OIDC", "false") == "true"
  def enable_ldap?         = ENV.fetch("SPARC_ENABLE_LDAP", "false") == "true"
  def enable_registration? = ENV.fetch("SPARC_ENABLE_USER_REGISTRATION", "false") == "true"
  def session_timeout      = ENV.fetch("SPARC_SESSION_TIMEOUT_MINUTES", "60").to_i

  # ── OIDC / OAuth2 ────────────────────────────────────────────────────────

  def oidc_issuer_url    = ENV.fetch("SPARC_OIDC_ISSUER_URL", nil)
  def oidc_client_id     = ENV.fetch("SPARC_OIDC_CLIENT_ID", nil)
  def oidc_client_secret = ENV.fetch("SPARC_OIDC_CLIENT_SECRET", nil)
  def oidc_redirect_uri  = ENV.fetch("SPARC_OIDC_REDIRECT_URI", nil)
  def oidc_scopes        = ENV.fetch("SPARC_OIDC_SCOPES", "openid profile email")
  def oidc_provider_title = ENV.fetch("SPARC_OIDC_PROVIDER_TITLE", "SSO")
  def oidc_force_mfa?    = ENV.fetch("SPARC_OIDC_FORCE_MFA", "false") == "true"

  # ── LDAP ──────────────────────────────────────────────────────────────────

  def ldap_host       = ENV.fetch("SPARC_LDAP_HOST", nil)
  def ldap_port       = ENV.fetch("SPARC_LDAP_PORT", "636").to_i
  def ldap_encryption = ENV.fetch("SPARC_LDAP_ENCRYPTION", "simple_tls")
  def ldap_bind_dn    = ENV.fetch("SPARC_LDAP_BIND_DN", nil)
  def ldap_bind_password = ENV.fetch("SPARC_LDAP_BIND_PASSWORD", nil)
  def ldap_base       = ENV.fetch("SPARC_LDAP_BASE", nil)
  def ldap_attribute  = ENV.fetch("SPARC_LDAP_ATTRIBUTE", "uid")

  # ── Logging ───────────────────────────────────────────────────────────────

  def log_to_stdout?      = ENV.fetch("SPARC_LOG_TO_STDOUT", "false") == "true"
  def structured_logging? = ENV.fetch("SPARC_STRUCTURED_LOGGING", "false") == "true"
  def log_level           = ENV.fetch("SPARC_LOG_LEVEL", "info")

  # ── SMTP / Email ──────────────────────────────────────────────────────────

  def enable_smtp?       = ENV.fetch("SPARC_ENABLE_SMTP", "false") == "true"
  def smtp_address       = ENV.fetch("SPARC_SMTP_ADDRESS", nil)
  def smtp_port          = ENV.fetch("SPARC_SMTP_PORT", "587").to_i
  def smtp_username      = ENV.fetch("SPARC_SMTP_USERNAME", nil)
  def smtp_password      = ENV.fetch("SPARC_SMTP_PASSWORD", nil)
  def smtp_auth          = ENV.fetch("SPARC_SMTP_AUTH", "plain")
  def smtp_starttls_auto = ENV.fetch("SPARC_SMTP_STARTTLS_AUTO", "true") == "true"
  def smtp_from_address  = ENV.fetch("SPARC_SMTP_FROM_ADDRESS", nil)

  # ── Security ──────────────────────────────────────────────────────────────

  def force_ssl? = ENV.fetch("FORCE_SSL", "true") == "true"

  # ── GitHub OAuth ──────────────────────────────────────────────────────────

  def github_enabled?      = ENV.fetch("SPARC_GITHUB_CLIENT_ID", "").present?
  def github_client_id     = ENV.fetch("SPARC_GITHUB_CLIENT_ID", nil)
  def github_client_secret = ENV.fetch("SPARC_GITHUB_CLIENT_SECRET", nil)

  # ── GitLab OAuth ─────────────────────────────────────────────────────────

  def gitlab_enabled?      = ENV.fetch("SPARC_GITLAB_CLIENT_ID", "").present?
  def gitlab_client_id     = ENV.fetch("SPARC_GITLAB_CLIENT_ID", nil)
  def gitlab_client_secret = ENV.fetch("SPARC_GITLAB_CLIENT_SECRET", nil)
  def gitlab_site          = ENV.fetch("SPARC_GITLAB_SITE", "https://gitlab.com")

  # ── Convenience ───────────────────────────────────────────────────────────

  def any_auth_enabled?
    enable_local_login? || enable_oidc? || enable_ldap? || github_enabled? || gitlab_enabled?
  end

  # Extract hostname from app_url for mailer configuration
  def app_host
    app_url.gsub(%r{\Ahttps?://}, "").split(":").first
  end
end
