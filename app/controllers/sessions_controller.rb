# frozen_string_literal: true

# Handles user authentication — local login, LDAP, and logout.
# OAuth/OIDC callbacks are handled by OmniauthCallbacksController.
class SessionsController < ApplicationController
  layout "login", only: :new

  # Skip auth gate for login/logout pages
  skip_before_action :require_authentication, only: [ :new, :create ], raise: false
  skip_before_action :check_password_reset, only: [ :new, :create, :destroy ], raise: false

  def new
    redirect_to root_path if signed_in?
  end

  def create
    if params[:auth_method] == "ldap"
      authenticate_ldap
    else
      authenticate_local
    end
  end

  def destroy
    if signed_in?
      AuditEvent.log(
        user: current_user,
        action: "logout",
        provider: "local",
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
    end

    end_session
    redirect_to root_path, success: "Signed out successfully."
  end

  private

  # ── Local Login ───────────────────────────────────────────────────────

  def authenticate_local
    unless SparcConfig.enable_local_login?
      redirect_to login_path, error: "Local login is not enabled."
      return
    end

    user = User.find_by("LOWER(email) = ?", params[:email].to_s.downcase.strip)

    if user&.active? && user&.authenticate(params[:password])
      start_session(user, ip_address: request.remote_ip)
      AuditEvent.log(
        user: user,
        action: "login_success",
        provider: "local",
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )

      return_to = session.delete(:return_to) || root_path
      redirect_to return_to, success: "Signed in successfully."
    else
      AuditEvent.log(
        user: user,
        action: "login_failure",
        provider: "local",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { email: params[:email].to_s }
      )

      flash.now[:error] = "Invalid email or password."
      render :new, status: :unprocessable_entity
    end
  end

  # ── LDAP Login ────────────────────────────────────────────────────────

  def authenticate_ldap
    unless SparcConfig.enable_ldap?
      redirect_to login_path, error: "LDAP authentication is not enabled."
      return
    end

    result = LdapAuthService.authenticate(params[:username], params[:password])

    if result && result[:email].present?
      user = User.find_by("LOWER(email) = ?", result[:email].downcase.strip)

      # Auto-create user from LDAP if not found
      if user.nil?
        user = User.create!(
          email: result[:email],
          display_name: result[:display_name],
          first_name: result[:first_name],
          last_name: result[:last_name],
          status: "active"
        )
      end

      unless user.active?
        redirect_to login_path, error: "Your account has been suspended. Contact an administrator."
        return
      end

      # Link LDAP identity
      identity = Identity.find_or_create_by!(provider: "ldap", uid: result[:dn]) do |id|
        id.user = user
        id.email = result[:email]
      end
      identity.update!(user: user) unless identity.user_id == user.id
      identity.touch_last_used!

      start_session(user, ip_address: request.remote_ip)
      AuditEvent.log(
        user: user,
        action: "login_success",
        provider: "ldap",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { username: params[:username] }
      )

      return_to = session.delete(:return_to) || root_path
      redirect_to return_to, success: "Signed in with LDAP."
    else
      AuditEvent.log(
        action: "login_failure",
        provider: "ldap",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { username: params[:username].to_s }
      )

      flash.now[:error] = "Invalid LDAP credentials."
      render :new, status: :unprocessable_entity
    end
  end
end
