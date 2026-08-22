# frozen_string_literal: true

# #1016 — REST API for issuing and revoking a user's API tokens.
#
#   GET    /api/v1/users/:user_id/api_tokens
#   POST   /api/v1/users/:user_id/api_tokens
#   DELETE /api/v1/users/:user_id/api_tokens/:id
#
# Found by the missing-endpoint axis of #995: the credential the API itself
# authenticates with could be issued and revoked only through a browser
# session, so rotating it required a human. Automation could not provision or
# retire its own credential, which is the case that most needs an API.
#
# The plaintext is returned ONCE, by `create`, and never afterwards — only the
# SHA-256 digest is stored (`ApiToken.generate!`). `index` therefore lists
# metadata and never a token value; there is nothing to list.
#
# NIST 800-53 Controls:
#   IA-5 Authenticator Management (plaintext shown once, digest at rest)
#   AC-3/AC-6 (instance-admin only), AU-12 Audit Record Generation
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class Api::V1::ApiTokensController < Api::V1::BaseController
  before_action :authorize_admin!
  before_action :set_user

  # GET /api/v1/users/:user_id/api_tokens
  def index
    result = paginate(@user.api_tokens.order(created_at: :desc), items: 50)

    render json: {
      data: result[:data].map { |token| serialize(token) },
      meta: result[:meta]
    }
  end

  # POST /api/v1/users/:user_id/api_tokens
  def create
    token = ApiToken.generate!(
      user: @user,
      name: token_name,
      expires_at: parse_expires_at,
      created_by: current_user
    )

    audit_log("api_token_created", subject: @user, metadata: { token_name: token.name })

    # The one and only time the plaintext exists outside the caller's hands.
    render json: {
      data: serialize(token).merge(
        token: token.plaintext_token,
        warning: "Copy this token now. It is not stored and cannot be retrieved again."
      )
    }, status: :created
  end

  # DELETE /api/v1/users/:user_id/api_tokens/:id
  def destroy
    token = @user.api_tokens.find(params[:id])
    name  = token.name
    token.destroy!

    audit_log("api_token_revoked", subject: @user, metadata: { token_name: name })

    render json: { data: { id: params[:id].to_i, name: name, revoked: true } }
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end

  # Both fields are optional, so an empty or absent `api_token` object is a
  # valid request rather than a missing parameter — but anything else inside it
  # is refused, not discarded (#995).
  def token_params
    @token_params ||=
      if params[:api_token].present?
        permit_strictly(:api_token, :name, :expires_in_days)
      else
        ActionController::Parameters.new.permit(:name, :expires_in_days)
      end
  end

  def token_name
    token_params[:name].presence || "API Token #{@user.api_tokens.count + 1}"
  end

  # Mirrors the web form's contract: a positive number of days sets an expiry,
  # anything else leaves the token non-expiring.
  def parse_expires_at
    days = token_params[:expires_in_days].to_i
    days.positive? ? days.days.from_now : nil
  end

  def serialize(token)
    {
      id: token.id,
      name: token.name,
      user_id: token.user_id,
      expires_at: token.expires_at&.utc&.iso8601,
      expired: token.expires_at.present? && token.expires_at <= Time.current,
      last_used_at: token.try(:last_used_at)&.utc&.iso8601,
      created_at: token.created_at.utc.iso8601
    }
  end

  def authorize_admin!
    raise NotAuthorizedError, "Not authorized to manage API tokens" unless current_user.admin?
  end
end
