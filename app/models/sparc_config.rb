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
#
# NIST 800-53 Controls:
#   CM-6 Configuration Settings (25+ SPARC_* env vars)
#   CM-7 Least Functionality (auth toggles default to disabled)
#   AC-7 Unsuccessful Logon Attempts (login failure handling)
#   AC-11 Device Lock (SPARC_SESSION_TIMEOUT_MINUTES)
#   IA-5 Authenticator Management (SPARC_PASSWORD_EXPIRY_DAYS)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
module SparcConfig
  VERSION = "1.2.3"

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
  def support_email = contact_email
  def welcome_text  = ENV.fetch("SPARC_WELCOME_TEXT", "Welcome to SPARC")

  # Configurable resources list — JSON array of {display_text, href} objects.
  # Falls back to default FedRAMP/OSCAL/MITRE links when not set.
  def resources
    raw = ENV["SPARC_RESOURCES"]
    if raw.present?
      JSON.parse(raw) rescue default_resources
    else
      default_resources
    end
  end

  def default_resources
    [
      { "display_text" => "FedRAMP 20x", "href" => "https://www.fedramp.gov/20x" },
      { "display_text" => "NIST OSCAL", "href" => "https://pages.nist.gov/OSCAL/" },
      { "display_text" => "MITRE Security Automation Framework", "href" => "https://saf.mitre.org/" }
    ]
  end

  # ── Organization ─────────────────────────────────────────────────────────

  def org_name           = ENV.fetch("SPARC_ORG_NAME", "Default Organization")
  def org_description    = ENV.fetch("SPARC_ORG_DESCRIPTION", nil)
  def org_address        = ENV.fetch("SPARC_ORG_ADDRESS", nil)
  def org_contact_person = ENV.fetch("SPARC_ORG_CONTACT_PERSON", nil)
  def org_contact_email  = ENV.fetch("SPARC_ORG_CONTACT_EMAIL", nil)

  # ── User Lifecycle ───────────────────────────────────────────────────────

  def inactivity_days      = ENV.fetch("SPARC_INACTIVITY_DAYS", "30").to_i
  def password_expiry_days = ENV.fetch("SPARC_PASSWORD_EXPIRY_DAYS", "30").to_i

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

  # ── API Authentication Mode ─────────────────────────────────────────────
  # Controls which auth method the REST API accepts:
  #   local  — SPARC-issued Bearer tokens only (default)
  #   oidc   — OIDC/Okta JWT tokens only
  #   hybrid — JWTs for humans + SPARC tokens for service accounts
  def api_auth_mode = ENV.fetch("SPARC_API_AUTH", "local")

  API_AUTH_MODES = %w[local oidc hybrid].freeze

  # ── Security ──────────────────────────────────────────────────────────────

  def force_ssl? = ENV.fetch("FORCE_SSL", "true") == "true"

  # ── Consent Banner ──────────────────────────────────────────────────────

  def banner_enabled?     = ENV.fetch("SPARC_BANNER_ENABLED", "false") == "true"
  def banner_message_path = ENV.fetch("SPARC_BANNER_MESSAGE", nil)

  # ── GitHub OAuth ──────────────────────────────────────────────────────────

  def github_enabled?      = ENV.fetch("SPARC_GITHUB_CLIENT_ID", "").present?
  def github_client_id     = ENV.fetch("SPARC_GITHUB_CLIENT_ID", nil)
  def github_client_secret = ENV.fetch("SPARC_GITHUB_CLIENT_SECRET", nil)

  # ── GitLab OAuth ─────────────────────────────────────────────────────────

  def gitlab_enabled?      = ENV.fetch("SPARC_GITLAB_CLIENT_ID", "").present?
  def gitlab_client_id     = ENV.fetch("SPARC_GITLAB_CLIENT_ID", nil)
  def gitlab_client_secret = ENV.fetch("SPARC_GITLAB_CLIENT_SECRET", nil)
  def gitlab_site          = ENV.fetch("SPARC_GITLAB_SITE", "https://gitlab.com")

  # ── DISA CCI ─────────────────────────────────────────────────────────
  # URL for the official DISA CCI XML ZIP archive.
  # Override with SPARC_DISA_CCI_URL for air-gapped or mirror environments.

  def disa_cci_url
    ENV.fetch("SPARC_DISA_CCI_URL", "https://dl.dod.cyber.mil/wp-content/uploads/stigs/zip/U_CCI_List.zip")
  end

  # Comma-separated list of NIST SP 800-53 revision numbers to include
  # when importing CCI mappings. Default: "4,5" (Rev 4 + Rev 5).
  # Add "6" when Rev 6 is published: SPARC_CCI_REVS=4,5,6

  def cci_revisions
    ENV.fetch("SPARC_CCI_REVS", "4,5").split(",").map(&:strip)
  end

  # ── Service Account Lifecycle ────────────────────────────────────────────

  def sa_inactivity_days = ENV.fetch("SPARC_SA_INACTIVITY_DAYS", "90").to_i

  # ── AWS Secrets Manager ──────────────────────────────────────────────────
  # Two-secret strategy aligned with sparc-iac #22:
  #   Secret 1: admin-credentials (break-glass, MFA-gated)
  #   Secret 2: app-config (JSON blob, ECS task role reads at boot)

  def aws_secrets_enabled?          = ENV.fetch("SPARC_AWS_SECRETS_ENABLED", "false") == "true"
  def aws_iam_db_auth_enabled?      = ENV.fetch("SPARC_AWS_IAM_DB_AUTH", "false") == "true"
  def app_config_secret_arn         = ENV.fetch("SPARC_APP_CONFIG_SECRET_ARN", nil)
  def admin_credentials_secret_arn  = ENV.fetch("SPARC_ADMIN_CREDENTIALS_SECRET_ARN", nil)
  def aws_region                    = ENV.fetch("SPARC_AWS_REGION", ENV.fetch("AWS_REGION", "us-east-1"))

  # ── Convenience ───────────────────────────────────────────────────────────

  def any_auth_enabled?
    enable_local_login? || enable_oidc? || enable_ldap? || github_enabled? || gitlab_enabled?
  end

  # Extract hostname from app_url for mailer configuration
  def app_host
    app_url.gsub(%r{\Ahttps?://}, "").split(":").first
  end
end
