# frozen_string_literal: true

module Admin
  # Admin interface for managing SPARC users. Restricted to Instance Admins.
  # Enhanced with search, pagination, and authorization-boundary-role visibility.
  class UsersController < ApplicationController
    include Pagy::Method

    before_action :authorize_admin!
    before_action :set_user, only: [ :show, :edit, :update, :suspend, :reactivate ]

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
        render :edit, status: :unprocessable_entity
      end
    end

    def suspend
      @user.update!(status: "suspended")
      audit_log("user_suspended", subject: @user,
        metadata: { target_user_id: @user.id, target_email: @user.email })
      redirect_to admin_user_path(@user), success: "User suspended."
    end

    def reactivate
      @user.update!(status: "active")
      audit_log("user_reactivated", subject: @user,
        metadata: { target_user_id: @user.id, target_email: @user.email })
      redirect_to admin_user_path(@user), success: "User reactivated."
    end

    private

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
