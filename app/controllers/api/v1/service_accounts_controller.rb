# frozen_string_literal: true

# #1013 — REST API for service accounts: the API-only identities pipelines,
# CI systems and third-party integrations authenticate as.
#
#   GET    /api/v1/service_accounts
#   POST   /api/v1/service_accounts
#   GET    /api/v1/service_accounts/:id
#   PATCH  /api/v1/service_accounts/:id
#   POST   /api/v1/service_accounts/:id/disable
#   POST   /api/v1/service_accounts/:id/enable
#   POST   /api/v1/service_accounts/:id/regenerate_token
#   DELETE /api/v1/service_accounts/:id
#
# Found by the missing-endpoint axis of #995, and the sharpest instance of it:
# every part of a service account's lifecycle was browser-only, so provisioning
# automation could not provision the identity it was going to run as. Rotating
# a compromised credential required a human with a browser session.
#
# `destroy` DEACTIVATES rather than deleting, exactly as the web path does. A
# service account is the actor on audit events, and deleting the row would
# orphan the record of what it did.
#
# NIST 800-53 Controls:
#   AC-2 Account Management (create / disable / enable / deactivate)
#   AC-3 Access Enforcement (endpoint scoping), AC-6 Least Privilege (admin opt-in)
#   AC-17 Remote Access (CIDR allowlist), IA-4 Identifier Management
#   IA-5 Authenticator Management (token generation, expiry, rotation)
#   AU-12 Audit Record Generation
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class Api::V1::ServiceAccountsController < Api::V1::BaseController
  DEFAULT_TOKEN_LIFETIME_DAYS = 90

  before_action :authorize_admin!
  before_action :set_service_account,
                only: %i[show update disable enable regenerate_token destroy]

  # GET /api/v1/service_accounts
  def index
    scope = User.service_accounts.order(:email)
    if params[:q].present?
      scope = scope.where(
        "email ILIKE :q OR display_name ILIKE :q OR first_name ILIKE :q",
        q: "%#{params[:q]}%"
      )
    end
    result = paginate(scope, items: 50)

    render json: {
      data: result[:data].map { |account| serialize(account) },
      meta: result[:meta]
    }
  end

  # GET /api/v1/service_accounts/:id
  def show
    render json: { data: serialize(@service_account, detailed: true) }
  end

  # POST /api/v1/service_accounts
  #
  # Creates the account AND its first token in one call, because an account
  # with no token cannot do anything and a caller would immediately have to
  # make a second request.
  def create
    account = User.new(service_account_params)
    account.service_account = true
    # Never used: a service account cannot sign in through the web UI. Set so
    # the record satisfies the same validations every user does.
    account.password = SecureRandom.hex(32)
    account.password_confirmation = account.password
    account.save!

    token = issue_token(account, name: "Initial token")

    audit_log("service_account_created", subject: account,
              metadata: { name: account.display_label, owner: account.owner&.email })

    render json: {
      data: serialize(account, detailed: true).merge(token_payload(token))
    }, status: :created
  end

  # PATCH /api/v1/service_accounts/:id
  def update
    @service_account.update!(service_account_params)

    audit_log("service_account_updated", subject: @service_account,
              metadata: { changes: @service_account.previous_changes.except("updated_at") })
    render json: { data: serialize(@service_account, detailed: true) }
  end

  # POST /api/v1/service_accounts/:id/disable
  def disable
    reason = params[:reason].presence || "admin_action"
    @service_account.disable!(reason: reason)

    audit_log("service_account_disabled", subject: @service_account,
              metadata: { reason: reason })
    render json: { data: serialize(@service_account.reload, detailed: true) }
  end

  # POST /api/v1/service_accounts/:id/enable
  def enable
    @service_account.enable!

    audit_log("service_account_enabled", subject: @service_account)
    render json: { data: serialize(@service_account.reload, detailed: true) }
  end

  # POST /api/v1/service_accounts/:id/regenerate_token
  #
  # Revokes EVERY existing token before issuing the new one. Rotation that
  # leaves the old credential working is not rotation.
  def regenerate_token
    revoked = @service_account.api_tokens.count
    @service_account.api_tokens.destroy_all

    token = issue_token(@service_account, name: "Regenerated token")

    audit_log("service_account_token_regenerated", subject: @service_account,
              metadata: { token_prefix: token.plaintext_token[0..11], revoked: revoked })

    render json: {
      data: serialize(@service_account.reload, detailed: true)
              .merge(token_payload(token))
              .merge(tokens_revoked: revoked)
    }
  end

  # DELETE /api/v1/service_accounts/:id
  def destroy
    @service_account.deactivate!(reason: "admin_deleted")

    audit_log("service_account_deleted", subject: @service_account)
    render json: {
      data: serialize(@service_account.reload).merge(
        deactivated: true,
        note: "Service accounts are deactivated rather than deleted, so the audit trail of what they did survives."
      )
    }
  end

  private

  def set_service_account
    @service_account = User.service_accounts.find(params[:id])
  end

  def service_account_params
    permit_strictly(:service_account,
      :email, :first_name, :last_name, :display_name, :owner_id, :admin,
      # Token shape is not an attribute of the account, but it is set in the
      # same request, so it is accepted here and consumed by issue_token.
      also_accepts: %i[expires_in_days allowed_endpoints allowed_cidrs]
    )
  end

  def issue_token(account, name:)
    ApiToken.generate!(
      user: account,
      name: name,
      expires_at: token_expiry,
      created_by: current_user,
      allowed_endpoints: list_param(:allowed_endpoints),
      allowed_cidrs: list_param(:allowed_cidrs)
    )
  end

  # Defaults to 90 days rather than never expiring: a non-expiring credential
  # for an unattended identity is the one most likely to outlive its purpose.
  def token_expiry
    days = params.dig(:service_account, :expires_in_days).presence || params[:expires_in_days].presence
    (days ? days.to_i : DEFAULT_TOKEN_LIFETIME_DAYS).days.from_now
  end

  # Accepts a JSON array (the natural API shape) or the web form's
  # comma/newline-separated string.
  def list_param(key)
    raw = params.dig(:service_account, key) || params[key]
    return [] if raw.blank?
    return raw.map(&:to_s).map(&:strip).reject(&:blank?) if raw.respond_to?(:map)

    raw.to_s.split(/[\r\n,]+/).map(&:strip).reject(&:blank?)
  end

  def token_payload(token)
    {
      token: token.plaintext_token,
      token_expires_at: token.expires_at&.utc&.iso8601,
      warning: "Copy this token now. It is not stored and cannot be retrieved again."
    }
  end

  def serialize(account, detailed: false)
    data = {
      id: account.id,
      email: account.email,
      display_name: account.display_label,
      service_account: true,
      status: account.status,
      admin: account.admin?,
      owner_id: account.owner_id,
      active_token_count: account.api_tokens.active.count
    }

    if detailed
      data[:first_name] = account.first_name
      data[:last_name] = account.last_name
      data[:owner_email] = account.owner&.email
      data[:tokens] = account.api_tokens.order(created_at: :desc).map do |token|
        { id: token.id, name: token.name,
          expires_at: token.expires_at&.utc&.iso8601,
          allowed_endpoints: token.allowed_endpoints,
          allowed_cidrs: token.allowed_cidrs,
          created_at: token.created_at.utc.iso8601 }
      end
      data[:created_at] = account.created_at.utc.iso8601
      data[:updated_at] = account.updated_at.utc.iso8601
    end

    data
  end

  def authorize_admin!
    raise NotAuthorizedError, "Not authorized to manage service accounts" unless current_user.admin?
  end
end
