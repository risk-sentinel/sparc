# frozen_string_literal: true

module Admin
  # Admin interface for managing SPARC users. Restricted to Instance Admins.
  # Enhanced with search, pagination, and authorization-boundary-role visibility.
  class UsersController < ApplicationController
    include Pagy::Method
    include ActionView::Helpers::DateHelper # time_ago_in_words, for the reset expiry notice

    before_action :authorize_admin!
    before_action :set_user, only: [ :show, :edit, :update, :suspend, :reactivate, :deactivate,
                                     :reset_security_keys, :reset_password, :email_password_reset ]

    USERS_PER_PAGE = 25

    def index
      scope = User.order(:email)
      scope = scope.where("email ILIKE :q OR display_name ILIKE :q OR first_name ILIKE :q OR last_name ILIKE :q", q: "%#{params[:q]}%") if params[:q].present?
      scope = scope.where(status: params[:status]) if params[:status].present?
      @pagy, @users = pagy(:offset, scope, limit: USERS_PER_PAGE)
      @roles = Role.sorted
    end

    def show
      @identities = @user.identities
      @instance_roles = @user.user_roles.includes(:role).where(authorization_boundary_id: nil)
      @authorization_boundary_roles = @user.user_roles.includes(:role, :authorization_boundary).where.not(authorization_boundary_id: nil)
      @audit_events = AuditEvent.for_user(@user).recent.limit(50)
    end

    # Admin-initiated account creation. Self-service registration is gated off
    # (SPARC_ENABLE_USER_REGISTRATION); this is the admin path to provision
    # accounts (e.g. local-login DAST test users). NIST AC-2.
    def new
      @user = User.new(status: "active")
      @instance_roles = Role.where(scope: "instance").sorted
    end

    def create
      # Thin client over the same provisioning contract as the API
      # (Api::V1::UsersController#create) — privilege-safe :admin/:status.
      @user = UserProvisioningService.new(actor: current_user).build(params.require(:user))

      # #877 — SPARC issues the first credential; the admin never chooses one.
      # A password an admin picks is one they know, and before this it survived
      # indefinitely because nothing forced a change. Skipped when local login
      # is off: handing a password to someone who will only ever arrive via
      # OIDC/PIV puts an unusable secret on screen.
      temporary = @user.assign_temporary_password if SparcConfig.enable_local_login?

      if @user.save
        sync_instance_roles
        audit_log("user_created", subject: @user,
          metadata: { target_user_id: @user.id, target_email: @user.email, uuid: @user.uuid,
                      admin: @user.admin?, status: @user.status })

        if temporary
          # Same audit action as a reset, so "how did this account get its first
          # credential" has one answer shape for an assessor to follow.
          audit_log("admin_temporary_password_issued", subject: @user,
            metadata: { target_user_id: @user.id, target_email: @user.email, provisioning: true })
          flash[:temporary_password] = temporary
        end

        redirect_to admin_user_path(@user),
          success: temporary ? "User created. Give them the temporary password over a channel you trust — " \
                               "they must change it at first sign-in." : "User created."
      else
        @instance_roles = Role.where(scope: "instance").sorted
        flash.now[:error] = @user.errors.full_messages.to_sentence
        render :new, status: :unprocessable_content
      end
    end

    def edit
      @instance_roles = Role.where(scope: "instance").sorted
      @authorization_boundary_roles_data = @user.user_roles.includes(:role, :authorization_boundary).where.not(authorization_boundary_id: nil)
      @available_authorization_boundaries = AuthorizationBoundary.order(:name)
      @available_authorization_boundary_roles = Role.where(scope: "authorization_boundary").sorted
    end

    def update
      @user.assign_attributes(user_params)
      @user.admin = params.dig(:user, :admin) == "1"
      if @user.save
        sync_instance_roles
        sync_authorization_boundary_roles
        redirect_to admin_user_path(@user), success: "User updated."
      else
        @instance_roles = Role.where(scope: "instance").sorted
        @authorization_boundary_roles_data = @user.user_roles.includes(:role, :authorization_boundary).where.not(authorization_boundary_id: nil)
        @available_authorization_boundaries = AuthorizationBoundary.order(:name)
        @available_authorization_boundary_roles = Role.where(scope: "authorization_boundary").sorted
        flash.now[:error] = @user.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_content
      end
    end

    def suspend
      @user.update!(status: "suspended")
      audit_log("user_suspended", subject: @user,
        metadata: { target_user_id: @user.id, target_email: @user.email, uuid: @user.uuid })
      redirect_to admin_user_path(@user), success: "User suspended."
    rescue ActiveRecord::RecordInvalid => e
      # #878 — suspending the last admin locks everyone out just as
      # deactivating does; the model refuses and this reports it.
      audit_log("user_suspend_refused", subject: @user,
        metadata: { target_user_id: @user.id, target_email: @user.email, reason: "last_active_admin" })
      redirect_to admin_user_path(@user), error: e.record.errors.full_messages.to_sentence
    end

    # Lockout recovery (#779): revoke all of a user's FIDO2 security keys so they
    # can re-enroll. The only recovery path — there are no self-service codes.
    def reset_security_keys
      count = @user.webauthn_credentials.destroy_all.size
      audit_log("admin_webauthn_reset", subject: @user,
        metadata: { target_user_id: @user.id, target_email: @user.email, keys_removed: count })
      redirect_to admin_user_path(@user),
        success: "Removed #{count} security #{'key'.pluralize(count)}. The user must re-enroll to sign in with a key."
    end

    # ── Password recovery (#841) ─────────────────────────────────────────
    #
    # The counterpart to reset_security_keys below: FIDO2 lockout had a recovery
    # path and passwords did not, so a forgotten local-login password could only
    # be cleared from a Rails console.
    #
    # Two routes, because deployments differ:
    #
    #   email_password_reset — the app sends a one-time link. Needs SMTP.
    #   reset_password       — a temporary password the admin hands over out of
    #                          band, forced to be changed at first sign-in. The
    #                          only route available with no outbound mail.
    #
    # In neither does the admin end up knowing a password the user keeps. The
    # temporary one is known to the admin BY DESIGN, which is exactly why it
    # cannot survive the first login.
    def reset_password
      return unless resettable?

      temporary = @user.issue_temporary_password!
      audit_log("admin_temporary_password_issued", subject: @user,
        metadata: { target_user_id: @user.id, target_email: @user.email })

      # Flash, not persisted: it is a live credential, and the database keeps
      # only the bcrypt digest.
      flash[:temporary_password] = temporary
      redirect_to admin_user_path(@user),
        success: "Temporary password issued. Give it to the user over a channel you trust — " \
                 "it is shown only now, and they must change it as soon as they sign in."
    end

    def email_password_reset
      return unless resettable?

      unless SparcConfig.enable_smtp?
        redirect_to admin_user_path(@user),
          error: "This instance has no mail configured (SPARC_SMTP_ADDRESS), so a reset link " \
                 "cannot be sent. Issue a temporary password instead."
        return
      end

      token = @user.issue_password_reset!
      PasswordResetMailer.reset_link(@user, token, issued_by: current_user.email).deliver_later
      audit_log("admin_password_reset_emailed", subject: @user,
        metadata: { target_user_id: @user.id, target_email: @user.email,
                    expires_at: @user.password_reset_expires_at&.iso8601 })

      redirect_to admin_user_path(@user),
        success: "Password reset link sent to #{@user.email}. It can be used once and expires " \
                 "#{time_ago_in_words(@user.password_reset_expires_at)} from now."
    end

    def reactivate
      force_reset = params[:force_password_reset] == "1"
      @user.reactivate!(force_password_reset: force_reset)
      audit_log("user_reactivated", subject: @user,
        metadata: { target_user_id: @user.id, target_email: @user.email, uuid: @user.uuid,
                    force_password_reset: force_reset })
      redirect_to admin_user_path(@user), success: "User reactivated."
    end

    def deactivate
      @user.deactivate!(reason: "admin_action")
      audit_log("user_deactivated", subject: @user,
        metadata: { target_user_id: @user.id, target_email: @user.email, uuid: @user.uuid,
                    reason: "admin_action" })
      redirect_to admin_user_path(@user), success: "User deactivated."
    rescue User::LastAdminError => e
      # #878 — a message, not a 500. Authentication gates on `active?`, so this
      # would have locked everyone out of administration with no self-service
      # way back.
      audit_log("user_deactivate_refused", subject: @user,
        metadata: { target_user_id: @user.id, target_email: @user.email, reason: "last_active_admin" })
      redirect_to admin_user_path(@user), error: e.message
    end

    private

    # A suspended or deactivated account must not be handed a working
    # credential — reactivate it deliberately first.
    def resettable?
      return true if @user.active?

      redirect_to admin_user_path(@user),
        error: "Only an active user can be issued a password reset. Reactivate the account first."
      false
    end

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.require(:user).permit(:display_name, :first_name, :last_name)
    end

    # Sync instance-scoped role checkboxes
    def sync_instance_roles
      role_ids = params.dig(:user, :role_ids)&.reject(&:blank?)&.map(&:to_i) || []
      @user.user_roles.where(authorization_boundary_id: nil).where.not(role_id: role_ids).destroy_all
      role_ids.each do |role_id|
        @user.user_roles.find_or_create_by!(role_id: role_id, authorization_boundary_id: nil)
      end
    end

    # Sync authorization-boundary-scoped role assignments from the edit form
    def sync_authorization_boundary_roles
      assignments = params.dig(:user, :authorization_boundary_roles) || []
      submitted_ids = []

      assignments.each do |pr|
        next if pr[:authorization_boundary_id].blank? || pr[:role_id].blank?
        ur = @user.user_roles.find_or_create_by!(
          authorization_boundary_id: pr[:authorization_boundary_id].to_i,
          role_id: pr[:role_id].to_i
        )
        submitted_ids << ur.id
      end

      # Remove any authorization boundary roles that were removed in the form
      keep_ids = params.dig(:user, :keep_authorization_boundary_role_ids)&.reject(&:blank?)&.map(&:to_i) || []
      ids_to_keep = (submitted_ids + keep_ids).uniq
      @user.user_roles.where.not(authorization_boundary_id: nil).where.not(id: ids_to_keep).destroy_all
    end
  end
end
