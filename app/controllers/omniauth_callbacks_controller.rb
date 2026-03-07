# frozen_string_literal: true

# Handles OAuth/OIDC callbacks from GitHub, GitLab, and generic OIDC
# providers. Finds or creates a User by email, links an Identity, and
# establishes a session.
class OmniauthCallbacksController < ApplicationController
  skip_before_action :require_authentication, raise: false
  skip_before_action :check_password_reset, raise: false
  skip_before_action :verify_authenticity_token, only: :create

  # POST /auth/:provider/callback
  def create
    auth = request.env["omniauth.auth"]

    if auth.blank?
      redirect_to login_path, error: "Authentication data missing."
      return
    end

    identity = Identity.from_omniauth(auth)
    email = (auth.info&.email || identity.email).to_s.downcase.strip

    if email.blank?
      redirect_to login_path, error: "No email returned from #{auth.provider}. Please ensure your email is public."
      return
    end

    user = identity.user || User.find_by("LOWER(email) = ?", email)

    if user.nil?
      # Auto-create user from OAuth — no password needed
      user = User.new(
        email: email,
        display_name: auth.info&.name,
        first_name: auth.info&.first_name,
        last_name: auth.info&.last_name,
        avatar_url: auth.info&.image,
        status: "active"
      )

      unless user.save
        redirect_to login_path, error: "Could not create account: #{user.errors.full_messages.to_sentence}"
        return
      end
    end

    unless user.active?
      redirect_to login_path, error: "Your account has been suspended. Contact an administrator."
      return
    end

    # Link identity to user
    identity.user = user
    identity.email = email
    identity.auth_data = auth.to_h.except("credentials")
    identity.save!
    identity.touch_last_used!

    start_session(user, ip_address: request.remote_ip)

    AuditEvent.log(
      user: user,
      action: "login_success",
      provider: auth.provider,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: { uid: auth.uid }
    )

    redirect_to (session.delete(:return_to) || root_path), success: "Signed in with #{auth.provider.titleize}."
  end

  # GET /auth/failure
  def failure
    message = params[:message] || "Unknown error"
    AuditEvent.log(
      action: "login_failure",
      provider: params[:strategy] || "unknown",
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: { error: message }
    )

    redirect_to login_path, error: "Authentication failed: #{message.humanize}"
  end
end
