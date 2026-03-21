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
  #   AC-6 Least Privilege (service accounts cannot be admin)
  #   AC-17 Remote Access (optional CIDR allowlist)
  #   IA-4 Identifier Management (UUID + sparc_sa_ prefix)
  #   IA-5 Authenticator Management (token generation, expiration, rotation)
  class ServiceAccountsController < ApplicationController
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

      if @service_account.save
        # Generate initial token
        expires_at = params[:expires_in_days].present? ? params[:expires_in_days].to_i.days.from_now : 90.days.from_now
        allowed_endpoints = parse_list_param(params[:allowed_endpoints])
        allowed_cidrs = parse_list_param(params[:allowed_cidrs])

        token = ApiToken.generate!(
          user: @service_account,
          name: "Initial token",
          expires_at: expires_at,
          created_by: current_user,
          allowed_endpoints: allowed_endpoints,
          allowed_cidrs: allowed_cidrs
        )

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
        render :new, status: :unprocessable_entity
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
        render :edit, status: :unprocessable_entity
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

    def regenerate_token
      # Revoke all existing tokens
      @service_account.api_tokens.destroy_all

      expires_at = params[:expires_in_days].present? ? params[:expires_in_days].to_i.days.from_now : 90.days.from_now
      allowed_endpoints = parse_list_param(params[:allowed_endpoints])
      allowed_cidrs = parse_list_param(params[:allowed_cidrs])

      token = ApiToken.generate!(
        user: @service_account,
        name: "Regenerated token",
        expires_at: expires_at,
        created_by: current_user,
        allowed_endpoints: allowed_endpoints,
        allowed_cidrs: allowed_cidrs
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
      params.require(:user).permit(:email, :first_name, :last_name, :display_name, :owner_id)
    end

    def service_account_update_params
      params.require(:user).permit(:email, :first_name, :last_name, :display_name, :owner_id)
    end

    def parse_list_param(param)
      return [] if param.blank?
      param.to_s.split(/[\r\n,]+/).map(&:strip).reject(&:blank?)
    end
  end
end
