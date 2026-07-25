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
    session[:auth_provider] = provider.to_s
    user.record_sign_in!(ip_address: ip_address)
  end

  # End the current session.
  def end_session
    reset_session
    @current_user = nil
  end

  # ── Session Timeout ───────────────────────────────────────────────────

  # Check if the session has timed out based on SPARC_SESSION_TIMEOUT_MINUTES.
  # Called as a before_action.
  def check_session_timeout
    return unless signed_in?

    last_active = session[:last_active_at]
    timeout = SparcConfig.session_timeout.minutes

    if last_active && Time.at(last_active) < timeout.ago
      end_session
      # 303 See Other so the browser issues a fresh GET to /login (not a Turbo
      # visit that could reuse a cached snapshot), landing on the login page
      # rendered with the relaxed form-action CSP + Cache-Control: no-store
      # (#649). end_session already reset_session'd, clearing the cookie.
      redirect_to login_path, status: :see_other,
                  warning: "Your session has expired. Please sign in again."
    else
      session[:last_active_at] = Time.current.to_i
    end
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

  private

  # The enrollment endpoints themselves, plus logout and the password flow, must
  # stay reachable — otherwise the gate loops or traps a user mid-password-reset.
  def webauthn_gate_exempt_route?
    %w[webauthn_credentials sessions passwords].include?(controller_name)
  end

  def webauthn_gate_exempt_user?(user)
    return true if user.service_account?
    return true if user.email.to_s.casecmp?(SparcConfig.admin_email.to_s)
    # `local` mode gates only local-password sessions; `all` gates everyone.
    return true if SparcConfig.require_fido2_mode == "local" && current_auth_provider != "local"

    false
  end

  # How the current session authenticated (set by start_session, #802).
  def current_auth_provider
    session[:auth_provider].to_s
  end
end
