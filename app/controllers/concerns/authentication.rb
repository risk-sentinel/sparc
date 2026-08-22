# frozen_string_literal: true

# Authentication concern for ApplicationController.
#
# Provides session management, current_user lookup, and
# the require_authentication gate. When no auth methods are
# enabled (SparcConfig.any_auth_enabled? == false), the gate
# is a no-op and all routes remain public — preserving backward
# compatibility for deployments that haven't configured auth yet.
#
# Session fixation prevention: reset_session is called before
# storing user_id after successful authentication.
#
# NIST 800-53 Controls:
#   IA-2  Identification and Authentication (Organizational Users)
#   AC-11 Device Lock / Session Lock (via check_session_timeout)
#   AC-12 Session Termination (via end_session)
#   IA-11 Re-authentication (session timeout forces re-auth)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :signed_in?, :controls_publicly_accessible?
  end

  class_methods do
    # Declare the READ actions of a Controls-layer controller as publicly
    # readable when `SPARC_PUBLIC_CATALOGS=true`, and authenticated otherwise
    # (#726, #974).
    #
    # This exists because the rule used to be TWO lines that had to agree:
    #
    #     skip_before_action :require_authentication, only: [ :index, :show ]
    #     before_action :require_authentication_unless_public_controls, only: [ :index, :show ]
    #
    # The skip alone makes the action unconditionally public. Writing it and
    # forgetting the gate is silent — nothing raises, no test fails, the screen
    # simply stops requiring a login. That is exactly what happened to
    # `CdefDocumentsController` and `ControlFamiliesController`: the CDEF
    # library and every control-family page were world-readable regardless of
    # the flag, and no configuration could turn it off.
    #
    # One declaration cannot be half-applied, and the action list cannot drift
    # between the two halves because it is written once.
    #
    #     public_controls_read only: [ :index, :show ]
    #
    # Read-only by construction: a caller that passes a mutating action is
    # refused, so this can never be the route by which a write becomes public.
    #
    # NIST 800-53: AC-3 Access Enforcement, CM-6 Configuration Settings.
    def public_controls_read(only:)
      actions = Array(only)
      forbidden = actions.map(&:to_s) & MUTATING_ACTION_NAMES
      if forbidden.any?
        raise ArgumentError,
              "public_controls_read is for READ actions only; refusing #{forbidden.join(', ')}. " \
              "Writes never become public in any posture (#974)."
      end

      skip_before_action :require_authentication, only: actions, raise: false
      before_action :require_authentication_unless_public_controls, only: actions
    end
  end

  # Action names that may never be declared publicly readable. Deliberately
  # broader than CRUD: anything that fetches, refreshes or imports is a write
  # in effect even when its verb is GET.
  MUTATING_ACTION_NAMES = %w[
    create update destroy edit new
    publish approve reject submit_for_review
    import do_import import_stig export
    refresh_cci refresh_aws_config refresh_aws_security_hub refresh_aws_labs
    bulk_destroy bulk_apply bulk_apply_preview bulk_apply_confirm
    update_metadata update_field update_statement update_scope set_baseline
  ].freeze

  # ── Current User ──────────────────────────────────────────────────────

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = if session[:user_id]
      User.find_by(id: session[:user_id], status: "active")
    end
  end

  def signed_in?
    current_user.present?
  end

  # ── Authentication Gate ───────────────────────────────────────────────

  # Call as before_action to require authentication.
  # No-op when all auth methods are disabled (backward compatible).
  def require_authentication
    return unless SparcConfig.any_auth_enabled?
    return if signed_in?

    session[:return_to] = request.fullpath if request.get? || request.head?
    redirect_to login_path, warning: "Please sign in to continue."
  end

  # ── Public Controls Gate (#726) ───────────────────────────────────────

  # Whether the Controls layer (catalogs, baselines, mappings) is visible /
  # readable for the current request. True when auth is disabled, when a
  # deployment opts into public sharing (SPARC_PUBLIC_CATALOGS=true), or when
  # the user is signed in. Both the header nav (visibility) and the
  # catalog/baseline/mapping read controllers (access) key off this, so the
  # nav never advertises a page the request cannot reach.
  #
  # NIST 800-53: AC-3 Access Enforcement.
  def controls_publicly_accessible?
    !SparcConfig.any_auth_enabled? || SparcConfig.public_catalogs? || signed_in?
  end

  # before_action for the public read actions of the Controls controllers.
  # Requires authentication unless the control library is configured public.
  def require_authentication_unless_public_controls
    require_authentication unless SparcConfig.public_catalogs?
  end

  # ── Session Management ────────────────────────────────────────────────

  # Start a new authenticated session. Resets session first to prevent
  # session fixation attacks. `provider` records HOW the user authenticated
  # ("local", "ldap", "oidc", "piv", "webauthn", …) so the mandatory-FIDO2 gate
  # can scope `local` mode to local-password sessions (#802). Defaults to
  # "local" — the strict default, so a caller that forgets to pass it errs
  # toward gating rather than exempting.
  def start_session(user, ip_address: nil, provider: "local")
    reset_session
    session[:user_id] = user.id
    session[:last_active_at] = Time.current.to_i
    # #860 — when this session began, for the absolute cap in
    # check_session_timeout. Set here because start_session is the ONLY writer
    # of session[:user_id] in the app: local, LDAP, OIDC, PIV, WebAuthn,
    # registration and the API cookie bridge all funnel through it, so every
    # session gets a start stamp without seven separate changes.
    session[:started_at] = Time.current.to_i
    session[:auth_provider] = provider.to_s
    user.record_sign_in!(ip_address: ip_address)
  end

  # End the current session.
  def end_session
    reset_session
    @current_user = nil
  end

  # ── Session Timeout ───────────────────────────────────────────────────

  # Two independent limits, both enforced here as a before_action:
  #
  #   IDLE      SPARC_SESSION_TIMEOUT_MINUTES (default 60) — time since the last
  #             request. Refreshed on every request.
  #   ABSOLUTE  SPARC_SESSION_MAX_HOURS (default 8) — time since sign-in, which
  #             nothing refreshes. #860.
  #
  # The absolute cap is what makes "each login establishes the user's rights"
  # true rather than approximate. Without it an active user is never asked to
  # authenticate again, so entitlements resolved at one login stay in force
  # indefinitely — including after the IdP has revoked them, since SPARC learns
  # about IdP-side changes only at the next sign-in.
  #
  # NIST 800-53: AC-11 (idle), AC-12 (absolute), IA-11 (re-authentication).
  def check_session_timeout
    return unless signed_in?

    if session_expired?
      end_session
      # 303 See Other so the browser issues a fresh GET to /login (not a Turbo
      # visit that could reuse a cached snapshot), landing on the login page
      # rendered with the relaxed form-action CSP + Cache-Control: no-store
      # (#649). end_session already reset_session'd, clearing the cookie.
      redirect_to login_path, status: :see_other,
                  warning: "Your session has expired. Please sign in again."
    else
      session[:last_active_at] = Time.current.to_i
      # #860 — adopt a session that predates the absolute cap. See
      # max_age_expired? for why this grandfathers rather than expires.
      session[:started_at] ||= Time.current.to_i
    end
  end

  # True when either limit is exceeded.
  def session_expired?
    idle_expired? || max_age_expired?
  end

  def idle_expired?
    last_active = session[:last_active_at]
    last_active.present? && Time.at(last_active) < SparcConfig.session_timeout.minutes.ago
  end

  # #860 — the absolute cap. Two deliberate behaviours:
  #
  # 1. `SPARC_SESSION_MAX_HOURS=0` disables it, restoring the idle-only
  #    behaviour for a deployment that needs long-lived sessions.
  #
  # 2. A session carrying NO `started_at` is ADOPTED rather than expired: it is
  #    stamped on the next request and capped from that moment. Those are
  #    sessions established before this shipped.
  #
  #    Expiring them instead was the first implementation and it was wrong in
  #    two ways. It forces every signed-in user to re-authenticate the moment
  #    the release lands — an availability cost paid by everyone for a control
  #    nobody had yet violated. And it is not confined to real upgrades: nothing
  #    outside start_session stamps the session, so any caller holding a session
  #    it did not create through that path is logged straight back out.
  #
  #    Adoption bounds a pre-existing session to `max_hours` from the upgrade,
  #    which is the same guarantee one sign-in later, without the flag day.
  def max_age_expired?
    max_hours = SparcConfig.session_max_hours
    return false if max_hours <= 0

    started_at = session[:started_at]
    return false if started_at.blank?

    Time.at(started_at) < max_hours.hours.ago
  end

  # ── Password Reset Check ──────────────────────────────────────────────

  # Force password change for bootstrapped admin accounts and expired passwords.
  def check_password_reset
    return unless signed_in?
    return if controller_name == "passwords" || controller_name == "sessions"

    if current_user.must_reset_password?
      redirect_to edit_password_path, warning: "You must change your password before continuing."
    elsif current_user.password_expired?
      redirect_to edit_password_path, warning: "Your password has expired. Please set a new password to continue."
    end
  end

  # ── Mandatory FIDO2 Enrollment Gate (#802) ────────────────────────────
  #
  # When SPARC_REQUIRE_FIDO2 is on, force a signed-in user with no registered
  # security key to the enrollment page before they can reach anything else —
  # org-wide mandatory hardware-key MFA, not opt-in. Mirrors check_password_reset
  # (runs after it, so a required password change happens first).
  #
  # Always exempt:
  #   - the enrollment/escape routes (or you build a redirect loop),
  #   - the break-glass bootstrap admin (SparcConfig.admin_email) — a shared
  #     local account fronted by an external role-checkout/PAM flow; no single
  #     person's key belongs on it,
  #   - service accounts (humanless — they authenticate by API token, never a key).
  # In `local` mode, only local-password sessions are gated (OIDC/LDAP/PIV rely
  # on their own MFA). NIST IA-2(1)/(2), IA-2(8).
  def check_webauthn_enrollment
    return unless SparcConfig.require_fido2?
    return unless signed_in?
    return if webauthn_gate_exempt_route?
    return if webauthn_gate_exempt_user?(current_user)
    return if current_user.webauthn_registered?

    redirect_to webauthn_credentials_path,
                warning: "Your organization requires a security key. Register one to continue."
  end

  # ── Required Auth-Method Gate (#805) ──────────────────────────────────
  #
  # When SPARC_REQUIRE_AUTH_METHODS is set, a signed-in user whose session was
  # established by a method NOT in the allowlist is bounced back to /login to
  # re-authenticate with an accepted method — "require OIDC or PIV" (phishing-
  # resistant), enforced in the app so it works on a single-listener `optional`
  # mTLS gateway. Same exemptions as #802 (break-glass admin + service accounts):
  # local login stays available to the break-glass account even when everyone
  # else is forced onto OIDC/PIV. NIST IA-2, IA-2(1)/(2), IA-2(8).
  def check_required_auth_method
    return unless SparcConfig.require_auth_methods?
    return unless signed_in?
    return if auth_gate_exempt_user?(current_user)
    return if auth_method_accepted?(current_auth_provider, SparcConfig.required_auth_methods)

    end_session # deny the non-accepted session; force re-auth via an allowed method
    redirect_to login_path, status: :see_other,
                warning: "Your organization requires signing in with: " \
                         "#{SparcConfig.required_auth_methods.join(', ')}. Please use one of those methods."
  end

  private

  # The enrollment endpoints themselves, plus logout and the password flow, must
  # stay reachable — otherwise the gate loops or traps a user mid-password-reset.
  def webauthn_gate_exempt_route?
    %w[webauthn_credentials sessions passwords].include?(controller_name)
  end

  def webauthn_gate_exempt_user?(user)
    return true if auth_gate_exempt_user?(user)
    # `local` mode gates only local-password sessions; `all` gates everyone.
    return true if SparcConfig.require_fido2_mode == "local" && current_auth_provider != "local"

    false
  end

  # Shared exemptions for the auth gates (#802/#805): the break-glass bootstrap
  # admin (a shared local account fronted by an external role-checkout/PAM flow)
  # and service accounts (humanless — they authenticate by API token).
  def auth_gate_exempt_user?(user)
    user.service_account? || user.email.to_s.casecmp?(SparcConfig.admin_email.to_s)
  end

  # True if `provider` satisfies any token in the `allowed` allowlist (#805).
  # Providers carry aliases so an operator can write "oidc" / "sso" / "fido2".
  def auth_method_accepted?(provider, allowed)
    return true if (provider_tokens(provider) & allowed).any?

    # #822 — an OIDC login can satisfy `piv` when the IdP itself performed
    # certificate-based authentication and said so in the token. Checked here
    # rather than by rewriting `auth_provider` to "piv", so the audit trail
    # still records HOW the person signed in (oidc) alongside WHAT it proved.
    allowed.include?("piv") && piv_asserted_by_idp?
  end

  # Set at the OIDC callback when the token carried an accepted acr/amr value.
  # Absent for every other provider and for any deployment that has not opted
  # in, so this is inert unless configured.
  def piv_asserted_by_idp? = session[:piv_assertion].present?

  def provider_tokens(provider)
    case provider
    when "openid_connect" then %w[openid_connect oidc sso]
    when "github"         then %w[github sso oauth]
    when "gitlab"         then %w[gitlab sso oauth]
    when "webauthn"       then %w[webauthn fido2]
    else                       [ provider ] # local, ldap, piv, api_token
    end
  end

  # How the current session authenticated (set by start_session, #802).
  def current_auth_provider
    session[:auth_provider].to_s
  end
end
