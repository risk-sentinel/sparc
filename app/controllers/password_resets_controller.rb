# frozen_string_literal: true

# #841 — redeeming an admin-issued password reset.
#
# Unauthenticated by necessity: the user cannot sign in, which is the whole
# problem. Authority comes from the token itself, which is single-use, expiring,
# and stored only as a SHA-256 digest.
#
# Deliberately does NOT ask for the current password. `PasswordsController` does,
# because it is a change flow for someone already signed in; requiring it here
# would reproduce the exact dead end this fixes.
#
# NIST 800-53 Controls:
#   IA-5 Authenticator Management (single-use, expiring, digest-at-rest)
#   AC-7 Unsuccessful Logon Attempts (lockout recovery)
#   AU-12 Audit Record Generation (redemption is audited)
class PasswordResetsController < ApplicationController
  skip_before_action :require_authentication, raise: false
  skip_before_action :check_password_reset, raise: false

  before_action :load_user_from_token

  # GET /password/reset/:token
  def edit
    # Intentionally empty. Everything this action needs is already done by the
    # `load_user_from_token` before_action: it resolves the token, and redirects
    # with a message when the token is unknown or expired. If control reaches
    # here, @user and @token are set and the only remaining job is to render
    # edit.html.erb — which Rails does implicitly.
  end

  # PATCH /password/reset/:token
  def update
    if @user.redeem_password_reset!(password: params[:new_password],
                                    password_confirmation: params[:new_password_confirmation])
      audit_log("password_reset_redeemed", subject: @user,
                metadata: { target_user_id: @user.id, target_email: @user.email })
      redirect_to login_path,
        success: "Your password has been set. Please sign in."
    else
      # Re-render rather than redirect: the token is in the URL and still valid,
      # so the user can correct the password without another admin round-trip.
      flash.now[:error] = @user.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_content
    end
  end

  private

  # A wrong token and an expired one are answered identically. Distinguishing
  # them tells an attacker which half of the guess was right.
  def load_user_from_token
    @token = params[:token]
    @user = User.find_by_password_reset_token(@token)

    return if @user

    redirect_to login_path,
      error: "That password reset link is invalid or has expired. Ask an administrator for a new one."
  end
end
