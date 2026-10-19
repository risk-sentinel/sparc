# frozen_string_literal: true

# #1016 — REST API for issuing and revoking a user's API tokens.
#
#   GET    /api/v1/users/:user_id/api_tokens
#   POST   /api/v1/users/:user_id/api_tokens
#   POST   /api/v1/users/:user_id/api_tokens/:id/renew     (#1176)
#   POST   /api/v1/users/:user_id/api_tokens/:id/reissue   (#1176)
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
#   IA-5 Authenticator Management (plaintext shown once, digest at rest;
#        #1176 lifetime: a service account's token must expire, within
#        SPARC_API_TOKEN_MAX_DAYS; renew overlaps for a grace window)
#   AC-3/AC-6 (instance-admin only), AU-12 Audit Record Generation
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class Api::V1::ApiTokensController < Api::V1::BaseController
  include ApiTokenLimits

  before_action :authorize_admin!
  before_action :set_user
  before_action :set_token, only: %i[destroy renew reissue]

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
      expires_at: expiry_from_days(requested_days),
      created_by: current_user,
      allowed_endpoints: token_list_param(token_params[:allowed_endpoints]) || [],
      allowed_cidrs: token_list_param(token_params[:allowed_cidrs]) || []
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

  # POST /api/v1/users/:user_id/api_tokens/:id/renew
  #
  # #1176 — a new token with the same name, endpoints, CIDRs and lifetime. The
  # old one keeps working until `replaced_token_expires_at`, at most
  # SPARC_API_TOKEN_RENEWAL_GRACE_DAYS from now.
  def renew
    replacement = @token.renew!(by: current_user)

    audit_log("api_token_renewed", subject: @user,
              metadata: { token_name: @token.name, replaced_token_id: @token.id,
                          new_token_id: replacement.id,
                          old_token_expires_at: @token.expires_at&.utc&.iso8601 })

    render json: {
      data: serialize(replacement).merge(
        token: replacement.plaintext_token,
        replaced_token_id: @token.id,
        replaced_token_expires_at: @token.expires_at&.utc&.iso8601,
        warning: "Copy this token now. It is not stored and cannot be retrieved again."
      )
    }, status: :created
  end

  # POST /api/v1/users/:user_id/api_tokens/:id/reissue
  #
  # #1176 — revoke now, and issue a replacement with the same limits.
  def reissue
    replacement = @token.reissue!(by: current_user)

    audit_log("api_token_reissued", subject: @user,
              metadata: { token_name: @token.name, revoked_token_id: @token.id,
                          new_token_id: replacement.id })

    render json: {
      data: serialize(replacement).merge(
        token: replacement.plaintext_token,
        revoked_token_id: @token.id,
        warning: "Copy this token now. It is not stored and cannot be retrieved again."
      )
    }, status: :created
  end

  # DELETE /api/v1/users/:user_id/api_tokens/:id
  def destroy
    token = @token
    name  = token.name
    token.destroy!

    audit_log("api_token_revoked", subject: @user, metadata: { token_name: name })

    render json: { data: { id: params[:id].to_i, name: name, revoked: true } }
  end

  private

  def set_user
    @user = User.find(params[:user_id])
  end

  def set_token
    @token = @user.api_tokens.find(params[:id])
  end

  # Every field is optional, so an empty or absent `api_token` object is a
  # valid request rather than a missing parameter — but anything else inside it
  # is refused, not discarded (#995).
  TOKEN_FIELDS = [ :name, :expires_in_days, :allowed_endpoints, :allowed_cidrs,
                   { allowed_endpoints: [], allowed_cidrs: [] } ].freeze

  def token_params
    @token_params ||=
      if params[:api_token].present?
        permit_strictly(:api_token, *TOKEN_FIELDS)
      else
        ActionController::Parameters.new.permit(*TOKEN_FIELDS)
      end
  end

  def token_name
    token_params[:name].presence || "API Token #{@user.api_tokens.count + 1}"
  end

  # Mirrors the web form's contract: a positive number of days sets an expiry
  # and 0 means never. Absent means never for a person, and the default
  # lifetime for a service account, which may not have none (#1176).
  def requested_days
    days = token_days_param(token_params[:expires_in_days])
    days.nil? && @user.service_account? ? ApiToken::DEFAULT_SERVICE_ACCOUNT_DAYS : days
  end

  def serialize(token)
    {
      id: token.id,
      name: token.name,
      user_id: token.user_id,
      expires_at: token.expires_at&.utc&.iso8601,
      expired: token.expires_at.present? && token.expires_at <= Time.current,
      never_expires: token.never_expires?,
      expiring_soon: token.expiring_soon?,
      allowed_endpoints: token.allowed_endpoints,
      allowed_endpoints_summary: token.endpoint_summary,
      allowed_cidrs: token.allowed_cidrs,
      last_used_at: token.try(:last_used_at)&.utc&.iso8601,
      created_at: token.created_at.utc.iso8601
    }
  end

  # #1044 — was a private authorize_admin! that SHADOWED the shared gate in
  # concerns/authorization.rb. Only the wording differed, so only the wording
  # is kept; the authority check now has exactly one definition.
  def admin_required_message = "Not authorized to manage API tokens"
end
