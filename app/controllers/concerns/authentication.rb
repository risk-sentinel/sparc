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
module Authentication
  extend ActiveSupport::Concern

  included do
    helper_method :current_user, :signed_in?
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

  # ── Session Management ────────────────────────────────────────────────

  # Start a new authenticated session. Resets session first to prevent
  # session fixation attacks.
  def start_session(user, ip_address: nil)
    reset_session
    session[:user_id] = user.id
    session[:last_active_at] = Time.current.to_i
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
      redirect_to login_path, warning: "Your session has expired. Please sign in again."
    else
      session[:last_active_at] = Time.current.to_i
    end
  end

  # ── Password Reset Check ──────────────────────────────────────────────

  # Force password change for bootstrapped admin accounts.
  def check_password_reset
    return unless signed_in?
    return unless current_user.must_reset_password?
    return if controller_name == "passwords" || controller_name == "sessions"

    redirect_to edit_password_path, warning: "You must change your password before continuing."
  end
end
