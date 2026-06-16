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
  VERSION = "1.9.0"

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

  # #548 — guard against meta-refresh trap on document show pages.
  # Documents in pending/processing for longer than this stop polling
  # and show a "stuck" message instead of looping every 3 seconds.
  def processing_stuck_minutes = ENV.fetch("SPARC_PROCESSING_STUCK_MINUTES", "5").to_i

  # #618 — server-side counterpart to the front-end "stuck" banner. The
  # StuckDocumentReaperJob transitions documents left in pending/processing
  # past this many minutes (with no live parse job) to a terminal state, so a
  # lost enqueue or dead worker can't strand a document forever. Set higher
  # than processing_stuck_minutes to avoid reaping a legitimately long parse.
  def document_reap_minutes = ENV.fetch("SPARC_DOCUMENT_REAP_MINUTES", "10").to_i

  # ── Authentication Toggles ────────────────────────────────────────────────
  # All default to false — features must be explicitly enabled.

  def enable_local_login?  = ENV.fetch("SPARC_ENABLE_LOCAL_LOGIN", "false") == "true"
  def enable_oidc?         = ENV.fetch("SPARC_ENABLE_OIDC", "false") == "true"
  def enable_ldap?         = ENV.fetch("SPARC_ENABLE_LDAP", "false") == "true"
  def enable_registration? = ENV.fetch("SPARC_ENABLE_USER_REGISTRATION", "false") == "true"
  def session_timeout      = ENV.fetch("SPARC_SESSION_TIMEOUT_MINUTES", "60").to_i

  # ── Dynamic Roles ────────────────────────────────────────────────────────
  # Configurable role lists for organizations and authorization boundaries.
  # Comma-separated lists via environment variables. Defaults to the
  # hardcoded role sets if not specified.

  def organization_roles
    roles = ENV.fetch("SPARC_ORGANIZATION_ROLES", "").split(",").map(&:strip).reject(&:blank?)
    roles.presence || OrganizationMembership::DEFAULT_ROLES
  end

  def auth_boundary_roles
    roles = ENV.fetch("SPARC_AUTH_BOUNDARY_ROLES", "").split(",").map(&:strip).reject(&:blank?)
    roles.presence || AuthorizationBoundaryMembership::DEFAULT_ROLES
  end

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

  # ── Upload Limits (#510) ─────────────────────────────────────────────────
  # Operators set caps in megabytes; SparcConfig does the byte math.
  # Single unified cap (max_upload_mb) applies to both the raw upload size
  # AND the uncompressed total of zip-based formats (xlsx). Teams who
  # legitimately need larger XLSX payloads raise the global cap — surfaces
  # the cost of that choice instead of burying it in a format-specific knob.
  # Avatar stays separate (small images shouldn't compete with document caps).

  def max_upload_mb     = ENV.fetch("SPARC_MAX_UPLOAD_MB", "50").to_i
  def max_avatar_mb     = ENV.fetch("SPARC_MAX_AVATAR_MB", "2").to_i
  def max_upload_bytes  = max_upload_mb * 1.megabyte
  def max_avatar_bytes  = max_avatar_mb * 1.megabyte

  # XLSX upload gate (#510). Default false — XLSX is hidden from
  # DocumentTypeRegistry unless explicitly enabled. Code-only flag;
  # intentionally not surfaced in public env-var documentation.
  def xlsx_uploads_enabled? = ENV.fetch("SPARC_ENABLE_XLSX_UPLOADS", "false") == "true"

  # #630 — Document review/approval gate. When true, trust-store documents
  # (Catalog, Profile, Baseline, CDEF) must be `approved` before they can be
  # published. Default false: the approval workflow is available but not
  # enforced, so existing publish flows are unchanged until an org enables it.
  def require_document_approval? = ENV.fetch("SPARC_REQUIRE_DOCUMENT_APPROVAL", "false") == "true"

  # ── Cookieless User-Data Subdomain (#515) ────────────────────────────────
  # User-uploaded blobs (SSP/SAR/CDEF/POAM JSON, XML, YAML, XLSX, evidence)
  # are served from a separate cookieless hostname. Even if a future code
  # change accidentally sets disposition: "inline" on a user-uploaded
  # HTML/SVG file, the browser script lives on the userdata.* origin and
  # can't read the SPARC session cookie (which is host-only on the main
  # app hostname per Rails default — verified, do NOT add Domain= to the
  # session cookie config; that would defeat the protection).
  #
  # By default the userdata host is derived as "userdata.<app-host>" from
  # SPARC_APP_URL — single operator setting drives both. Edge cases
  # (per-tenant subdomains, on-prem split DNS) can override via
  # SPARC_USERDATA_HOST.
  #
  # Pairs with sparc-iac DNS/ALB/cert for the userdata.* hostname.

  def app_uri
    URI.parse(app_url)
  rescue URI::InvalidURIError
    nil
  end

  def userdata_host
    return ENV["SPARC_USERDATA_HOST"] if ENV["SPARC_USERDATA_HOST"].present?
    return nil unless app_uri&.host
    "userdata.#{app_uri.host}"
  end

  def userdata_protocol
    app_uri&.scheme || "https"
  end

  # ── Rate Limiting (#513) ─────────────────────────────────────────────────
  # Rack::Attack throttle thresholds, operator-tunable per the project
  # pattern. Defaults are conservative (favor availability over
  # aggressive blocking); tighten for high-security tenants. Safelist
  # CIDRs bypass all throttles — used for internal health-check IPs,
  # NLB targets, etc. Loopback addresses are safelisted by default for
  # development convenience.
  def rate_limiting_enabled?               = ENV.fetch("SPARC_RATE_LIMITING_ENABLED", "true") == "true"
  def rate_limit_uploads_per_5min_per_ip   = ENV.fetch("SPARC_RATE_LIMIT_UPLOADS_PER_5MIN_PER_IP", "30").to_i
  def rate_limit_uploads_per_hour_per_user = ENV.fetch("SPARC_RATE_LIMIT_UPLOADS_PER_HOUR_PER_USER", "100").to_i
  def rate_limit_api_writes_per_minute     = ENV.fetch("SPARC_RATE_LIMIT_API_WRITES_PER_MINUTE", "300").to_i
  def rate_limit_login_failures_per_minute = ENV.fetch("SPARC_RATE_LIMIT_LOGIN_FAILURES_PER_MIN", "5").to_i
  # CSP violation report beacons (#528, epic #650). Per-IP cap so a misbehaving
  # or hostile client can't flood the log sink. Generous default — a page with
  # several violations fires a burst legitimately.
  def rate_limit_csp_reports_per_minute    = ENV.fetch("SPARC_RATE_LIMIT_CSP_REPORTS_PER_MIN", "60").to_i

  def rate_limit_safelist_cidrs
    ENV.fetch("SPARC_RATE_LIMIT_SAFELIST_CIDRS", "127.0.0.1,::1").split(",").map(&:strip).reject(&:empty?)
  end

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

  # ── OAuth form-action origins (CSP) ───────────────────────────────────────
  # External IdP origins the login page must be allowed to POST-redirect to.
  # The login form starts SSO with a same-origin POST to /auth/:provider, which
  # OmniAuth answers with a 302 to the IdP. Chromium enforces the CSP
  # `form-action` directive against EVERY hop in that redirect chain, so the IdP
  # origin must be explicitly allowlisted or the button is silently blocked.
  # Firefox does not re-check redirects, which masked the bug. See issue #593.
  #
  # Returns scheme://host[:port] origins (no path), suitable for direct
  # interpolation into a CSP directive. Only enabled providers are included.
  #
  # NIST 800-53: SC-7 (Boundary Protection), SC-18 (Mobile Code — CSP)
  def oauth_form_action_origins
    origins = []
    origins << "https://github.com"          if github_enabled?
    origins << oauth_origin(gitlab_site)      if gitlab_enabled?
    origins << oauth_origin(oidc_issuer_url)  if enable_oidc? && oidc_issuer_url.present?
    origins.compact.uniq
  end

  # Normalize a URL to its CSP source origin (scheme://host[:port], no path).
  # Returns nil for blank/invalid input so callers can compact it away.
  def oauth_origin(url)
    return nil if url.blank?

    uri = URI.parse(url)
    return nil if uri.scheme.blank? || uri.host.blank?

    default_port = uri.scheme == "https" ? 443 : 80
    port = uri.port && uri.port != default_port ? ":#{uri.port}" : ""
    "#{uri.scheme}://#{uri.host}#{port}"
  rescue URI::InvalidURIError
    nil
  end

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

  # ── AWS Labs CDEF Fetch (#466) ────────────────────────────────────────────
  # Runtime ingestion of OSCAL Component Definitions from
  # awslabs/oscal-content-for-aws-services. Opt-in so air-gapped tenants are
  # unaffected by default. Apache 2.0 attribution is maintained in
  # docs/compliance/THIRD_PARTY_NOTICES.md and the top-level NOTICE file.
  def aws_labs_cdef_enabled?     = ENV.fetch("SPARC_AWS_LABS_CDEF_ENABLED", "false") == "true"
  def aws_labs_cdef_repo         = ENV.fetch("SPARC_AWS_LABS_CDEF_REPO", "awslabs/oscal-content-for-aws-services")
  def aws_labs_cdef_branch       = ENV.fetch("SPARC_AWS_LABS_CDEF_BRANCH", "main")
  def aws_labs_github_token      = ENV["SPARC_AWS_LABS_GITHUB_TOKEN"]

  # AWS Labs CDEFs change on the order of weeks, not days. Default the
  # recurring refresh to every 7 days so audit logs and runtime traffic stay
  # quiet; operators who track a fast-moving fork can lower the interval.
  # Minimum 1, maximum 90 (a quarter) so the schedule remains parseable by
  # Fugit and the refresh stays within a reasonable window for compliance.
  def aws_labs_cdef_refresh_interval_days
    raw = ENV.fetch("SPARC_AWS_LABS_CDEF_REFRESH_INTERVAL_DAYS", "7").to_i
    raw.clamp(1, 90)
  end

  # When unset, defaults to the OSCAL versions SPARC's loaded schemas
  # already support — so the import only pulls CDEFs we can validate.
  def aws_labs_oscal_versions
    raw = ENV["SPARC_AWS_LABS_OSCAL_VERSIONS"]
    if raw.present?
      raw.split(",").map(&:strip).reject(&:blank?)
    elsif defined?(OscalSchema) && OscalSchema.table_exists?
      OscalSchema.distinct.pluck(:oscal_version).compact
    else
      []
    end
  end

  # ── Convenience ───────────────────────────────────────────────────────────

  def any_auth_enabled?
    enable_local_login? || enable_oidc? || enable_ldap? || github_enabled? || gitlab_enabled?
  end

  # Extract hostname from app_url for mailer configuration
  def app_host
    app_url.gsub(%r{\Ahttps?://}, "").split(":").first
  end
end
