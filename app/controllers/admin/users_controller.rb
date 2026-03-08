# frozen_string_literal: true

module Admin
  # Admin interface for managing SPARC users. Restricted to Instance Admins.
  class UsersController < ApplicationController
    before_action :authorize_admin!
    before_action :set_user, only: [ :show, :edit, :update, :suspend, :reactivate ]

    def index
      @users = User.order(:email)
      @roles = Role.sorted
    end

    def show
      @identities = @user.identities
      @user_roles = @user.user_roles.includes(:role)
      @audit_events = AuditEvent.for_user(@user).recent.limit(50)
    end

    def edit
      @roles = Role.sorted
    end

    def update
      @user.assign_attributes(user_params)
      @user.admin = params.dig(:user, :admin) == "1"
      if @user.save
        sync_roles
        redirect_to admin_user_path(@user), success: "User updated."
      else
        @roles = Role.sorted
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

    def sync_roles
      role_ids = params.dig(:user, :role_ids)&.reject(&:blank?)&.map(&:to_i) || []
      @user.user_roles.where(project_id: nil).where.not(role_id: role_ids).destroy_all
      role_ids.each do |role_id|
        @user.user_roles.find_or_create_by!(role_id: role_id, project_id: nil)
      end
    end
  end
end
