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
  VERSION = "1.12.3"

  extend self

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
    raw = ENV.fetch("SPARC_RESOURCES", nil)
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

  # ── Artifact storage hygiene (#690) ───────────────────────────────────────

  # ArtifactStorageReaperJob is report-only unless this is true. With full
  # per-version retention + purge-off (#680), storage grows by design, so
  # destructive cleanup of truly-unreferenced blobs is opt-in and coordinated
  # with the S3 lifecycle policy (sparc-iac#476).
  def artifact_reaper_purge? = ENV.fetch("SPARC_ARTIFACT_REAPER_PURGE", "false") == "true"

  # Grace window: never reap a blob younger than this, so an in-flight upload
  # (blob created before its attachment is saved) is never mistaken for orphaned.
  def artifact_reaper_min_age_hours = ENV.fetch("SPARC_ARTIFACT_REAPER_MIN_AGE_HOURS", "24").to_i

  # ── Authentication Toggles ────────────────────────────────────────────────
  # All default to false — features must be explicitly enabled.

  def enable_local_login?  = ENV.fetch("SPARC_ENABLE_LOCAL_LOGIN", "false") == "true"
  def enable_oidc?         = ENV.fetch("SPARC_ENABLE_OIDC", "false") == "true"
  def enable_ldap?         = ENV.fetch("SPARC_ENABLE_LDAP", "false") == "true"
  def enable_registration? = ENV.fetch("SPARC_ENABLE_USER_REGISTRATION", "false") == "true"
  def fido2_enabled?       = ENV.fetch("SPARC_FIDO2_ENABLED", "false") == "true"  # WebAuthn security keys (#779)

  # PIV / CAC smart-card auth (#779, Track B). The mTLS handshake + DoD PKI
  # validation + revocation happen at the proxy/ALB (sparc-iac); SPARC consumes
  # the *validated* client cert it forwards. piv_cert_header carries the PEM;
  # piv_verify_header must equal piv_verify_success or SPARC rejects (fail-closed
  # — never trust a cert the proxy didn't verify, and the proxy strips any
  # client-supplied copies of these headers).
  def enable_piv?          = ENV.fetch("SPARC_ENABLE_PIV", "false") == "true"
  def piv_cert_header      = ENV.fetch("SPARC_PIV_CERT_HEADER", "X-SSL-Client-Cert")
  def piv_verify_header    = ENV.fetch("SPARC_PIV_VERIFY_HEADER", "X-SSL-Client-Verify")
  def piv_verify_success   = ENV.fetch("SPARC_PIV_VERIFY_SUCCESS", "SUCCESS")
  def session_timeout      = ENV.fetch("SPARC_SESSION_TIMEOUT_MINUTES", "60").to_i

  # Public visibility of the Controls layer (catalogs, baselines, mappings).
  # Default false = secure-by-default: when auth is enabled, guests neither
  # see the Controls nav nor can read those pages. Deployments that front
  # SPARC with their own network auth (VPN, etc.) and want to share the
  # control library set SPARC_PUBLIC_CATALOGS=true. See #726. (AC-3)
  def public_catalogs? = ENV.fetch("SPARC_PUBLIC_CATALOGS", "false") == "true"

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

  # ── Environments (#770) ──────────────────────────────────────────────────
  # The selectable set of deployment environments a Boundary can be tagged
  # with. Configurable via SPARC_ENVIRONMENTS_LIST as comma-separated
  # "Name:CODE" pairs (e.g. "Development:DEV,Production:PROD"); falls back to
  # the six standard RMF environments when unset. A missing ":CODE" defaults
  # the code to the name.
  #
  # Returns [{ name:, code:, value: }], where `value` is the stored token
  # (name parameterized with underscores). `value` is what persists on
  # boundaries.environment, so the legacy enum values production/development/
  # staging/test round-trip unchanged (their slugs equal their names).
  DEFAULT_ENVIRONMENTS = [
    "Development:DEV", "Test:TEST", "Staging:STAG",
    "User Acceptance Testing:UAT", "Quality Assurance:QA", "Production:PROD"
  ].freeze

  def environments
    raw = ENV.fetch("SPARC_ENVIRONMENTS_LIST", "").split(",").map(&:strip).reject(&:blank?)
    (raw.presence || DEFAULT_ENVIRONMENTS).map do |entry|
      name, code = entry.split(":", 2).map(&:strip)
      { name: name, code: code.presence || name, value: name.parameterize(separator: "_") }
    end
  end

  # Stored tokens for validation (boundaries.environment inclusion).
  def environment_values = environments.map { |e| e[:value] }

  # value => "Name (CODE)" for display in dropdowns and badges.
  def environment_label(value)
    env = environments.find { |e| e[:value] == value }
    env ? "#{env[:name]} (#{env[:code]})" : value.to_s.titleize
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

  # LDAP TLS trust (NIST SC-8 / IA-2). Server-cert verification is ON by
  # default; the connection trusts the container/system CA store (see the
  # custom-CA container-trust mechanism, #774). SPARC_LDAP_CA_FILE points at a
  # directory CA without baking it into the image; SPARC_LDAP_TLS_VERIFY=false
  # disables verification for legacy internal directories (insecure — logs a
  # warning on every connection).
  def ldap_ca_file     = ENV.fetch("SPARC_LDAP_CA_FILE", nil)
  def ldap_tls_verify? = ENV.fetch("SPARC_LDAP_TLS_VERIFY", "true") == "true"

  # ── Logging ───────────────────────────────────────────────────────────────

  def log_to_stdout?      = ENV.fetch("SPARC_LOG_TO_STDOUT", "false") == "true"
  def structured_logging? = ENV.fetch("SPARC_STRUCTURED_LOGGING", "false") == "true"
  def log_level           = ENV.fetch("SPARC_LOG_LEVEL", "info")

  # ── Artifact retention (#680/#686) ────────────────────────────────────────

  # When true, each minted ArtifactVersion gets an INDEPENDENT physical copy of
  # its content instead of sharing the current blob by reference. Off by default:
  # reference-based retention still resolves every version to its exact bytes with
  # no duplication. Enable for stronger per-version immutability / WORM (pairs with
  # S3 Object Lock in sparc-iac), at the cost of storage + a copy on each mint.
  def artifact_copy_per_version? = ENV.fetch("SPARC_ARTIFACT_COPY_PER_VERSION", "false") == "true"

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

  # ── HDF / OSCAL translation (#449, #648) ─────────────────────────────────
  # SPARC_HDF_NORMALIZE_BASELINES was removed in #764. It injected an empty
  # `baselines: []` to work around hdf-cli 3.2.0 requiring that field for
  # hdf→oscal-sar (upstream mitre/hdf-libs#104). Fixed upstream in 3.3.1, so
  # from the 3.4.1 pin the injection is not merely unnecessary — it is the only
  # thing that lets non-HDF input through: garbage converts at exit 0 with the
  # field injected and is correctly rejected without it. Removing it restores
  # the "garbage in → 422" contract.

  # Allowlist of certified hdf-cli tool versions for the translation surface.
  # Empty (default) = accept whatever version is baked into the image (chosen
  # at build via the HDF_LIBS_VERSION Docker build arg). When set (e.g.
  # "3.4.1,3.4.0"), the translation endpoints refuse to run on an
  # uncertified hdf-cli build.
  def hdf_allowed_versions
    ENV.fetch("SPARC_HDF_ALLOWED_VERSIONS", "").split(",").map(&:strip).reject(&:empty?)
  end

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
    return ENV.fetch("SPARC_USERDATA_HOST", nil) if ENV.fetch("SPARC_USERDATA_HOST", nil).present?
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

  # ── Environment / Rules Header (#682) ─────────────────────────────────────
  # Operator-configurable header bar shown on EVERY screen describing the
  # deployment environment and its rules of behavior (e.g. "PRODUCTION —
  # Authorized use only"). Default-off: an empty SPARC_HEADER_TEXT hides it.
  #
  # NIST 800-53: AC-8 System Use Notification — an all-screens rules-of-behavior
  # notice that complements the login-time consent banner (#190, AC-8 at auth).
  #
  # Colors are OPERATOR-defined. SPARC deliberately does NOT enforce WCAG
  # contrast on supplied values (the deployment owns its choices, per #682),
  # but every value IS validated against a strict CSS color grammar before use
  # to prevent style/attribute injection (input validation, not accessibility).

  # SPARC brand defaults — #ffffff text on --sparc-primary #1f6fa5 = 5.42:1,
  # which passes WCAG AA for normal text. Keep these in sync with the
  # `.sparc-env-header` defaults in app/assets/stylesheets/sparc-theme.css.
  HEADER_DEFAULT_TEXT_COLOR      = "#ffffff"
  HEADER_DEFAULT_HIGHLIGHT_COLOR = "#1f6fa5"

  # Permitted CSS color forms: #rgb / #rgba / #rrggbb / #rrggbbaa and
  # rgb()/rgba() with numeric components. Anything else falls back to default.
  # (Single-line, no /x mode — `#` would start a comment under /x.)
  HEADER_COLOR_PATTERN =
    %r{\A(?:\#(?:[0-9a-fA-F]{3,4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})|rgba?\(\s*\d{1,3}(?:\s*,\s*\d{1,3}){2}(?:\s*,\s*(?:0|1|0?\.\d+))?\s*\))\z}

  def header_text     = ENV.fetch("SPARC_HEADER_TEXT", "").to_s
  def header_enabled? = header_text.strip.present?

  def header_text_color
    safe_header_color(ENV.fetch("SPARC_HEADER_TEXT_COLOR", nil), HEADER_DEFAULT_TEXT_COLOR)
  end

  def header_highlight_color
    safe_header_color(ENV.fetch("SPARC_HEADER_HIGHLIGHT_COLOR", nil), HEADER_DEFAULT_HIGHLIGHT_COLOR)
  end

  # Returns the supplied color when it matches the CSS color grammar, else the
  # brand default. Guards against CSS/attribute injection from operator input;
  # does NOT enforce contrast (operator-owned per #682).
  def safe_header_color(value, fallback)
    value = value.to_s.strip
    HEADER_COLOR_PATTERN.match?(value) ? value : fallback
  end

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
  def aws_labs_github_token      = ENV.fetch("SPARC_AWS_LABS_GITHUB_TOKEN", nil)

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
    raw = ENV.fetch("SPARC_AWS_LABS_OSCAL_VERSIONS", nil)
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
    enable_local_login? || enable_oidc? || enable_ldap? || github_enabled? || gitlab_enabled? || fido2_enabled? || enable_piv?
  end

  # Extract hostname from app_url for mailer configuration
  def app_host
    app_url.gsub(%r{\Ahttps?://}, "").split(":").first
  end
end
