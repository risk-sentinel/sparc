# frozen_string_literal: true

module Admin
  # Admin interface for managing SPARC users. Restricted to Instance Admins.
  # Enhanced with search, pagination, and project-role visibility.
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
      @instance_roles = @user.user_roles.includes(:role).where(project_id: nil)
      @project_roles = @user.user_roles.includes(:role, :project).where.not(project_id: nil)
      @audit_events = AuditEvent.for_user(@user).recent.limit(50)
    end

    def edit
      @instance_roles = Role.where(scope: "instance").sorted
      @project_roles_data = @user.user_roles.includes(:role, :project).where.not(project_id: nil)
      @available_projects = Project.order(:name)
      @available_project_roles = Role.where(scope: "project").sorted
    end

    def update
      @user.assign_attributes(user_params)
      @user.admin = params.dig(:user, :admin) == "1"
      if @user.save
        sync_instance_roles
        sync_project_roles
        redirect_to admin_user_path(@user), success: "User updated."
      else
        @instance_roles = Role.where(scope: "instance").sorted
        @project_roles_data = @user.user_roles.includes(:role, :project).where.not(project_id: nil)
        @available_projects = Project.order(:name)
        @available_project_roles = Role.where(scope: "project").sorted
        flash.now[:error] = @user.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    def suspend
      @user.update!(status: "suspended")
      AuditEvent.log(
        user: current_user,
        action: "user_suspended",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { target_user_id: @user.id, target_email: @user.email }
      )
      redirect_to admin_user_path(@user), success: "User suspended."
    end

    def reactivate
      @user.update!(status: "active")
      AuditEvent.log(
        user: current_user,
        action: "user_reactivated",
        ip_address: request.remote_ip,
        user_agent: request.user_agent,
        metadata: { target_user_id: @user.id, target_email: @user.email }
      )
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
      @user.user_roles.where(project_id: nil).where.not(role_id: role_ids).destroy_all
      role_ids.each do |role_id|
        @user.user_roles.find_or_create_by!(role_id: role_id, project_id: nil)
      end
    end

    # Sync project-scoped role assignments from the edit form
    def sync_project_roles
      assignments = params.dig(:user, :project_roles) || []
      submitted_ids = []

      assignments.each do |pr|
        next if pr[:project_id].blank? || pr[:role_id].blank?
        ur = @user.user_roles.find_or_create_by!(
          project_id: pr[:project_id].to_i,
          role_id: pr[:role_id].to_i
        )
        submitted_ids << ur.id
      end

      # Remove any project roles that were removed in the form
      keep_ids = params.dig(:user, :keep_project_role_ids)&.reject(&:blank?)&.map(&:to_i) || []
      ids_to_keep = (submitted_ids + keep_ids).uniq
      @user.user_roles.where.not(project_id: nil).where.not(id: ids_to_keep).destroy_all
    end
  end
end
