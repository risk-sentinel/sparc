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
    load_consent_banner
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

  # ── Consent Banner ────────────────────────────────────────────────────

  BANNER_ALLOWED_TAGS = %w[p br strong em ul ol li h1 h2 h3 h4 h5 h6 a span div].freeze
  BANNER_ALLOWED_ATTRS = %w[href class style].freeze

  def load_consent_banner
    return unless SparcConfig.banner_enabled?

    raw_path = SparcConfig.banner_message_path
    if raw_path.blank?
      Rails.logger.warn("[ConsentBanner] SPARC_BANNER_ENABLED=true but SPARC_BANNER_MESSAGE is not set")
      return
    end

    # Resolve relative paths against Rails.root
    path = Pathname.new(raw_path).absolute? ? raw_path : Rails.root.join(raw_path).to_s

    unless File.exist?(path)
      Rails.logger.warn("[ConsentBanner] Banner file not found: #{path}")
      return
    end

    raw_content = File.read(path, encoding: "UTF-8")
    @consent_banner_content = helpers.sanitize(raw_content, tags: BANNER_ALLOWED_TAGS, attributes: BANNER_ALLOWED_ATTRS)
  rescue StandardError => e
    Rails.logger.error("[ConsentBanner] Failed to read banner file: #{e.message}")
    @consent_banner_content = nil
  end

  # ── Local Login ───────────────────────────────────────────────────────

  def authenticate_local
    unless SparcConfig.enable_local_login?
      redirect_to login_path, error: "Local login is not enabled."
      return
    end

    user = User.find_by("LOWER(email) = ?", params[:email].to_s.downcase.strip)

    # Show specific message for deactivated accounts (before generic auth check)
    if user&.deactivated?
      AuditEvent.log(
        user: user,
        action: "login_failure",
        provider: "local",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { email: params[:email].to_s, reason: "account_deactivated" }
      )

      flash.now[:error] = "Your account has been deactivated. Contact an administrator."
      render :new, status: :unprocessable_entity
      return
    end

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
        redirect_to login_path, error: "Your account is not active. Contact an administrator."
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
