# frozen_string_literal: true

# Self-service user registration. Only available when both
# SPARC_ENABLE_LOCAL_LOGIN and SPARC_ENABLE_USER_REGISTRATION are true.
class RegistrationsController < ApplicationController
  layout "login"

  skip_before_action :require_authentication, raise: false
  skip_before_action :check_password_reset, raise: false

  before_action :ensure_registration_enabled

  def new
    redirect_to root_path if signed_in?
    @user = User.new
  end

  def create
    @user = User.new(registration_params)
    @user.status = "active"

    if @user.save
      AuditEvent.log(
        user: @user,
        action: "login_success",
        provider: "local",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { registration: true }
      )

      start_session(@user, ip_address: request.remote_ip)
      redirect_to root_path, success: "Account created! Welcome to SPARC."
    else
      flash.now[:error] = @user.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(:email, :password, :password_confirmation, :first_name, :last_name, :display_name)
  end

  def ensure_registration_enabled
    return if SparcConfig.enable_local_login? && SparcConfig.enable_registration?

    redirect_to login_path, error: "User registration is not enabled."
  end
end
