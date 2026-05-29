# frozen_string_literal: true

# Handles user authentication — local login, LDAP, and logout.
# OAuth/OIDC callbacks are handled by OmniauthCallbacksController.
class SessionsController < ApplicationController
  layout "login", only: :new

  # Skip auth gate for login/logout pages
  skip_before_action :require_authentication, only: [ :new, :create ], raise: false
  skip_before_action :check_password_reset, only: [ :new, :create, :destroy ], raise: false

  # #593 — The login page starts SSO via same-origin POST forms to
  # /auth/:provider, which OmniAuth answers with a 302 to the external IdP.
  # Chromium enforces the global `form-action 'self'` (see
  # config/initializers/content_security_policy.rb) against every redirect hop,
  # so it silently blocks the OAuth button; Firefox does not, which masked the
  # bug. Relax form-action to the enabled IdP origins on the LOGIN PAGE ONLY —
  # every other page keeps the strict 'self' policy. All other CSP directives
  # (script-src nonce, etc.) are inherited from the global policy unchanged.
  #
  # NIST 800-53: SC-7 (Boundary Protection), SC-18 (Mobile Code — CSP)
  content_security_policy(only: :new) do |policy|
    policy.form_action :self, *SparcConfig.oauth_form_action_origins
  end

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

    # Service accounts cannot log in via web UI — API tokens only
    if user&.service_account?
      AuditEvent.log(
        user: user,
        action: "login_failure",
        provider: "local",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { email: params[:email].to_s, reason: "service_account_web_login", auth_method: "local" }
      )

      flash.now[:error] = "Service accounts cannot log in via the web interface. Use API tokens instead."
      render :new, status: :unprocessable_entity
      return
    end

    # Show specific message for deactivated accounts (before generic auth check)
    if user&.deactivated?
      AuditEvent.log(
        user: user,
        action: "login_failure",
        provider: "local",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { email: params[:email].to_s, reason: "account_deactivated", auth_method: "local" }
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
        user_agent: request.user_agent,
        metadata: { auth_method: "local" }
      )

      return_to = session.delete(:return_to) || root_path
      redirect_to return_to, success: "Signed in successfully."
    else
      # #587 — classify the generic failure path so operators can tell
      # invalid_password from no_local_password from unknown_email,
      # etc., without console-diving. User-facing message stays
      # generic to prevent email enumeration.
      reason = LoginFailureReason.classify(user: user, password: params[:password])
      AuditEvent.log(
        user: user,
        action: "login_failure",
        provider: "local",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { email: params[:email].to_s, reason: reason, auth_method: "local" }
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
        metadata: { username: params[:username], auth_method: "ldap" }
      )

      return_to = session.delete(:return_to) || root_path
      redirect_to return_to, success: "Signed in with LDAP."
    else
      # #587 — LDAP credential rejection. LdapAuthService returns nil
      # or an empty email on bad bind; we can't distinguish unknown-
      # dn from wrong-password without a richer return shape from the
      # service. Use ldap_bind_failed as the single reason for now;
      # a follow-up could widen LdapAuthService to surface the
      # specific LDAP result code.
      AuditEvent.log(
        action: "login_failure",
        provider: "ldap",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { username: params[:username].to_s, reason: "ldap_bind_failed", auth_method: "ldap" }
      )

      flash.now[:error] = "Invalid LDAP credentials."
      render :new, status: :unprocessable_entity
    end
  end
end
