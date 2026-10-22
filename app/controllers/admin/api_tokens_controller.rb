# Admin: issue, renew, reissue and revoke a user's API tokens (people and
# service accounts alike — a service account is a User).
#
# NIST 800-53 Controls:
#   IA-5 Authenticator Management (lifetime, renewal, reissue — #1176)
#   AC-3/AC-6 (endpoint limits from ApiEndpointCatalog), AU-2/AU-12 (audit)
class Admin::ApiTokensController < ApplicationController
  include ApiTokenLimits

  before_action :authorize_admin!
  before_action :set_user
  before_action :set_token, only: %i[edit update destroy renew reissue]

  def create
    token = ApiToken.generate!(
      user: @user,
      name: token_attrs[:name].presence || "API Token #{@user.api_tokens.count + 1}",
      expires_at: expiry_from_days(requested_days),
      created_by: current_user,
      allowed_endpoints: picked_endpoints(token_attrs[:allowed_endpoints]) || [],
      allowed_cidrs: token_list_param(token_attrs[:allowed_cidrs]) || []
    )

    audit_log("api_token_created", subject: @user, metadata: { token_name: token.name })

    flash[:success] = "API token created. Copy it now — it won't be shown again."
    flash[:api_token] = token.plaintext_token
    redirect_back_to_owner
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    flash[:error] = "Token not created: #{e.respond_to?(:record) ? e.record.errors.full_messages.to_sentence : e.message}"
    redirect_back_to_owner
  end

  # #1233 — change an existing token's endpoint and CIDR limits in place. The
  # token keeps its value, so no client has to swap credentials.
  def edit
    return unless @token.expired?

    flash[:error] = "An expired token's limits cannot be changed. Renew or reissue it."
    redirect_back_to_owner
  end

  def update
    change = @token.update_limits!(
      allowed_endpoints: picked_endpoints(token_attrs[:allowed_endpoints]) || [],
      allowed_cidrs: token_list_param(token_attrs[:allowed_cidrs]) || []
    )

    audit_log("api_token_limits_changed", subject: @user,
              metadata: { token_name: @token.name, token_id: @token.id }.merge(change))

    flash[:success] = "Limits for '#{@token.name}' updated. They apply from the token's next request."
    redirect_back_to_owner
  rescue ActiveRecord::RecordInvalid, ArgumentError => e
    @error = e.respond_to?(:record) ? e.record.errors.full_messages.to_sentence : e.message
    @submitted_endpoints = token_list_param(token_attrs[:allowed_endpoints])
    @submitted_cidrs = token_list_param(token_attrs[:allowed_cidrs])
    flash.now[:error] = "Limits not changed: #{@error}"
    render :edit, status: :unprocessable_content
  end

  # #1176 — a new token with the same limits; this one keeps working for the
  # renewal grace window.
  def renew
    replacement = @token.renew!(by: current_user)

    audit_log("api_token_renewed", subject: @user,
              metadata: { token_name: @token.name, replaced_token_id: @token.id,
                          new_token_id: replacement.id,
                          old_token_expires_at: @token.expires_at&.utc&.iso8601 })

    flash[:success] = "Token renewed. Copy the new token now. The old one keeps working until " \
                      "#{@token.expires_at&.strftime('%Y-%m-%d %H:%M UTC') || 'it is revoked'}."
    flash[:api_token] = replacement.plaintext_token
    redirect_back_to_owner
  rescue ActiveRecord::RecordInvalid => e
    flash[:error] = "Token not renewed: #{e.record.errors.full_messages.to_sentence}"
    redirect_back_to_owner
  end

  # #1176 — revoke now and issue a replacement with the same limits.
  def reissue
    replacement = @token.reissue!(by: current_user)

    audit_log("api_token_reissued", subject: @user,
              metadata: { token_name: @token.name, revoked_token_id: @token.id,
                          new_token_id: replacement.id })

    flash[:success] = "Token reissued. The old token stopped working. Copy the new one now."
    flash[:api_token] = replacement.plaintext_token
    redirect_back_to_owner
  rescue ActiveRecord::RecordInvalid => e
    flash[:error] = "Token not reissued: #{e.record.errors.full_messages.to_sentence}"
    redirect_back_to_owner
  end

  def destroy
    @token.destroy!

    audit_log("api_token_revoked", subject: @user, metadata: { token_name: @token.name })

    flash[:success] = "API token '#{@token.name}' revoked."
    redirect_back_to_owner
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end

  def set_token
    @token = @user.api_tokens.find(params[:id])
  end

  def token_attrs
    params[:api_token] || ActionController::Parameters.new
  end

  # Not given: a service account gets the default lifetime (it may not have
  # none); a person's token keeps the old default, never expiring. "0" is the
  # form's "Never", which ApiToken refuses for a service account.
  def requested_days
    days = token_days_param(token_attrs[:expires_in_days])
    days.nil? && @user.service_account? ? ApiToken::DEFAULT_SERVICE_ACCOUNT_DAYS : days
  end

  # A service account's tokens are managed from its own page.
  def redirect_back_to_owner
    redirect_to @user.service_account? ? admin_service_account_path(@user) : admin_user_path(@user)
  end
end
