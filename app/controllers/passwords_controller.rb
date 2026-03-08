# frozen_string_literal: true

# Handles forced password changes for bootstrapped admin accounts
# and voluntary password changes for any authenticated user.
class PasswordsController < ApplicationController
  before_action :require_authentication

  def edit
    # Renders app/views/passwords/edit.html.erb
  end

  def update
    if current_user.authenticate(params[:current_password])
      if current_user.update(password: params[:new_password], password_confirmation: params[:new_password_confirmation], must_reset_password: false, password_changed_at: Time.current)
        AuditEvent.log(
          user: current_user,
          action: "password_change",
          provider: "local",
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
        redirect_to root_path, success: "Password updated successfully."
      else
        flash.now[:error] = current_user.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    else
      flash.now[:error] = "Current password is incorrect."
      render :edit, status: :unprocessable_entity
    end
  end
end
