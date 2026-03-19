class Admin::ApiTokensController < ApplicationController
  before_action :authorize_admin!
  before_action :set_user

  def create
    token = ApiToken.generate!(
      user: @user,
      name: params[:api_token]&.[](:name).presence || "API Token #{@user.api_tokens.count + 1}",
      expires_at: parse_expires_at
    )

    audit_log("api_token_created", subject: @user, metadata: { token_name: token.name })

    flash[:success] = "API token created. Copy it now — it won't be shown again."
    flash[:api_token] = token.plaintext_token
    redirect_to admin_user_path(@user)
  end

  def destroy
    token = @user.api_tokens.find(params[:id])
    token.destroy!

    audit_log("api_token_revoked", subject: @user, metadata: { token_name: token.name })

    flash[:success] = "API token '#{token.name}' revoked."
    redirect_to admin_user_path(@user)
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end

  def parse_expires_at
    days = params[:api_token]&.[](:expires_in_days).to_i
    days > 0 ? days.days.from_now : nil
  end
end
