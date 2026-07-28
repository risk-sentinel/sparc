# frozen_string_literal: true

# #573 — Bearer-token to Rails-session cookie bridge.
#
# Single endpoint: POST /api/v1/sessions/from_token
#
# Inputs:    Authorization: Bearer <token>  (SPARC SA or OIDC JWT, per
#                                            SPARC_API_AUTH mode)
# On valid:  204 No Content + Set-Cookie: _sparc_session=...
# On bad:    401 Unauthorized, no Set-Cookie, audit-logged
#
# Why this controller inherits from ApplicationController (not the
# Api::V1::BaseController which inherits from ActionController::API):
# we need session + cookies middleware to actually set the bridged
# cookie. The standard API base intentionally skips that middleware.
# We re-include ApiAuthentication so Bearer-token validation still
# works the same way as the rest of /api/v1/*.
#
# Security:
#   - Same Bearer-token authentication path as every other /api/v1/
#     endpoint (token revocation, expiry, scope, CIDR allowlist all
#     enforced upstream by ApiAuthentication#authenticate_api_token!)
#   - No CSRF guard (the caller sends a Bearer, not a cookie)
#   - Bridged session inherits SPARC_SESSION_TIMEOUT_MINUTES — no
#     longer-lived than a form-login session
#   - api_session_bridged emitted on success; api_session_bridge_failed
#     on every rejected attempt (so failed bridges are visible in
#     the audit log alongside login_failure events)
#
class Api::V1::SessionsController < ApplicationController
  include ApiAuthentication

  # Bearer-only endpoint; no form-CSRF, no session-required gate, no
  # session-timeout check (we're CREATING the session here), no
  # forced-password-reset gate. Each `raise: false` so adding the
  # controller doesn't blow up if the parent removes one of these.
  #
  # CodeQL `rb/csrf-protection-disabled` (alert #22) flags the first line.
  # There is no cookie-based session to forge here: the only credential this
  # endpoint accepts is a Bearer token, which an attacker's page cannot cause a
  # browser to attach cross-origin. The skip is written controller-wide rather
  # than `only:`-scoped, but this controller has exactly ONE action
  # (`from_token`, the sole route) — so if a second action is ever added here,
  # scope this skip to `from_token` at the same time.
  skip_before_action :verify_authenticity_token, raise: false
  skip_before_action :require_authentication,    raise: false
  skip_before_action :check_session_timeout,     raise: false
  skip_before_action :check_password_reset,      raise: false

  def from_token
    token_string = extract_bearer_token
    if token_string.blank?
      audit_bridge_failure!("missing_token")
      render json: { error: "Missing or invalid Authorization header. Use: Authorization: Bearer <token>" },
             status: :unauthorized
      return
    end

    # Reuse the standard API-token auth pipeline. On failure, this
    # renders a 401 JSON envelope itself — we just have to fire the
    # failure audit alongside and stop processing.
    authenticate_api_token!

    if @current_user.nil?
      audit_bridge_failure!("invalid_token")
      return
    end

    start_session(@current_user, ip_address: request.remote_ip, provider: "api_token")
    audit_bridge_success!

    head :no_content
  end

  private

  def audit_bridge_success!
    AuditEvent.log(
      user:       @current_user,
      action:     "api_session_bridged",
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: {
        auth_mode:          @current_auth_mode,
        is_service_account: @current_user.service_account?
      }
    )
  end

  def audit_bridge_failure!(reason)
    AuditEvent.log(
      action:     "api_session_bridge_failed",
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata:   { reason: reason }
    )
  end
end
