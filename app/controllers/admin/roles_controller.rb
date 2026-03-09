# frozen_string_literal: true

module Admin
  # CRUD interface for managing SPARC role definitions and their
  # granular permissions. Restricted to Instance Admins.
  class RolesController < ApplicationController
    before_action :authorize_admin!
    before_action :set_role, only: [ :show, :edit, :update, :destroy ]

    def index
      @roles = Role.sorted
    end

    def show
      @user_roles = @role.user_roles.includes(:user, :project).order("users.email")
    end

    def new
      @role = Role.new(scope: "project")
    end

    def create
      @role = Role.new(role_params)
      @role.assign_permissions(params.dig(:role, :permissions) || {})

      if @role.save
        audit_log("role_created", subject: @role,
          metadata: { role_id: @role.id, role_name: @role.name })
        redirect_to admin_role_path(@role), success: "Role created."
      else
        flash.now[:error] = @role.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      @role.assign_attributes(role_params)
      @role.assign_permissions(params.dig(:role, :permissions) || {})

      if @role.save
        audit_log("role_updated", subject: @role,
          metadata: { role_id: @role.id, role_name: @role.name })
        redirect_to admin_role_path(@role), success: "Role updated."
      else
        flash.now[:error] = @role.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @role.user_roles.exists?
        redirect_to admin_role_path(@role),
          error: "Cannot delete a role that is assigned to users. Remove all assignments first."
        return
      end

      audit_log("role_deleted", subject: @role,
        metadata: { role_id: @role.id, role_name: @role.name })
      @role.destroy!
      redirect_to admin_roles_path, success: "Role deleted."
    end

    private

    def set_role
      @role = Role.find(params[:id])
    end

    def role_params
      params.require(:role).permit(:name, :display_name, :scope, :description, :sort_order)
    end
  end
end
