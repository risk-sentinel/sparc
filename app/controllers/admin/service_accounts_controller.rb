# frozen_string_literal: true

module Admin
  # Admin interface for managing service accounts — API-only users
  # for pipelines, CI/CD systems, and third-party integrations.
  #
  # Service accounts authenticate via SPARC API tokens (sparc_sa_ prefix)
  # and cannot log in via the web UI.
  #
  # NIST 800-53 Controls:
  #   AC-2 Account Management (create/disable/enable/delete lifecycle)
  #   AC-3 Access Enforcement (endpoint scoping via allowed_endpoints)
  #   AC-6 Least Privilege (admin flag is per-SA opt-in, never implicit)
  #   AC-17 Remote Access (optional CIDR allowlist)
  #   IA-4 Identifier Management (UUID + sparc_sa_ prefix)
  #   IA-5 Authenticator Management (token generation, expiration, rotation)
  class ServiceAccountsController < ApplicationController
    include ApiTokenLimits

    before_action :authorize_admin!
    before_action :set_service_account, only: [ :show, :edit, :update, :disable, :enable, :regenerate_token, :destroy ]

    def index
      scope = User.service_accounts.order(:email)
      scope = scope.where("email ILIKE :q OR display_name ILIKE :q OR first_name ILIKE :q", q: "%#{params[:q]}%") if params[:q].present?
      @service_accounts = scope
    end

    def show
      @tokens = @service_account.api_tokens.order(created_at: :desc)
      @audit_events = AuditEvent.for_user(@service_account).recent.limit(25)
    end

    def new
      @service_account = User.new(service_account: true)
      @human_users = User.human_users.active.order(:email)
    end

    def create
      @service_account = User.new(service_account_params)
      @service_account.service_account = true
      @service_account.password = SecureRandom.hex(32)
      @service_account.password_confirmation = @service_account.password

      token = create_with_initial_token
      if token
        AuditEvent.log(
          user: current_user,
          action: "service_account_created",
          subject: @service_account,
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          metadata: { name: @service_account.display_label, owner: @service_account.owner&.email }
        )

        flash[:api_token] = token.plaintext_token
        redirect_to admin_service_account_path(@service_account), notice: "Service account created. Copy the API token now — it won't be shown again."
      else
        @human_users = User.human_users.active.order(:email)
        @selected_endpoints = token_list_param(params[:allowed_endpoints]) || []
        render :new, status: :unprocessable_content
      end
    end

    def edit
      @human_users = User.human_users.active.order(:email)
    end

    def update
      if @service_account.update(service_account_update_params)
        AuditEvent.log(
          user: current_user,
          action: "service_account_updated",
          subject: @service_account,
          ip_address: request.remote_ip,
          user_agent: request.user_agent,
          metadata: { changes: @service_account.previous_changes.except("updated_at") }
        )
        redirect_to admin_service_account_path(@service_account), notice: "Service account updated."
      else
        @human_users = User.human_users.active.order(:email)
        render :edit, status: :unprocessable_content
      end
    end

    def disable
      reason = params[:reason].presence || "admin_action"
      @service_account.disable!(reason: reason)

      AuditEvent.log(
        user: current_user,
        action: "service_account_disabled",
        subject: @service_account,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { reason: reason }
      )
      redirect_to admin_service_account_path(@service_account), notice: "Service account disabled."
    end

    def enable
      @service_account.enable!

      AuditEvent.log(
        user: current_user,
        action: "service_account_enabled",
        subject: @service_account,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
      redirect_to admin_service_account_path(@service_account), notice: "Service account re-enabled."
    end

    # Revoke every token and issue one. #1176: limits and lifetime the form
    # does not send are carried over from the newest token. The button sends
    # none, and before #1176 that issued a token with no limits at all.
    def regenerate_token
      token = ApiToken.regenerate_for!(
        @service_account, by: current_user,
        expires_in_days: token_days_param(params[:expires_in_days]),
        allowed_endpoints: token_list_param(params[:allowed_endpoints]),
        allowed_cidrs: token_list_param(params[:allowed_cidrs])
      )

      AuditEvent.log(
        user: current_user,
        action: "service_account_token_regenerated",
        subject: @service_account,
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { token_prefix: token.plaintext_token[0..11] }
      )

      flash[:api_token] = token.plaintext_token
      redirect_to admin_service_account_path(@service_account), notice: "Token regenerated. Copy the new API token now — it won't be shown again."
    rescue ActiveRecord::RecordInvalid, ArgumentError => e
      message = e.respond_to?(:record) ? e.record.errors.full_messages.to_sentence : e.message
      redirect_to admin_service_account_path(@service_account), alert: "Token not regenerated: #{message}"
    end

    def destroy
      @service_account.deactivate!(reason: "admin_deleted")

      AuditEvent.log(
        user: current_user,
        action: "service_account_deleted",
        subject: @service_account,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
      redirect_to admin_service_accounts_path, notice: "Service account deactivated."
    end

    private

    def set_service_account
      @service_account = User.service_accounts.find(params[:id])
    end

    def service_account_params
      params.require(:user).permit(:email, :first_name, :last_name, :display_name, :owner_id, :admin)
    end

    def service_account_update_params
      params.require(:user).permit(:email, :first_name, :last_name, :display_name, :owner_id, :admin)
    end

    def submitted_endpoints
      picked_endpoints(params[:allowed_endpoints]) || []
    end

    # #1176 — the account and its first token are checked, then saved,
    # together. A token the rules refuse (an unknown endpoint, a lifetime past
    # the cap) leaves no account behind, and its errors show on the form beside
    # the account's. Returns the token, or nil with the errors on
    # @service_account.
    def create_with_initial_token
      account_valid = @service_account.valid?
      attrs = initial_token_attrs
      return nil unless attrs

      probe = ApiToken.new(attrs.merge(user: @service_account, token_digest: "validation-probe"))
      unless probe.valid?
        probe.errors.full_messages.each { |m| @service_account.errors.add(:base, "Token: #{m}") }
      end
      return nil unless account_valid && probe.errors.empty?

      User.transaction do
        @service_account.save!
        ApiToken.generate!(user: @service_account, **attrs)
      end
    end

    def initial_token_attrs
      days = token_days_param(params[:expires_in_days]) || ApiToken::DEFAULT_SERVICE_ACCOUNT_DAYS
      { name: "Initial token", expires_at: expiry_from_days(days), created_by: current_user,
        allowed_endpoints: submitted_endpoints, allowed_cidrs: token_list_param(params[:allowed_cidrs]) || [] }
    rescue ArgumentError => e
      @service_account.errors.add(:base, "Token: #{e.message}")
      nil
    end
  end
end
