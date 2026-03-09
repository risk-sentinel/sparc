# frozen_string_literal: true

module Admin
  # Admin interface for managing project-level user role assignments.
  # Restricted to Instance Admins.
  class ProjectsController < ApplicationController
    before_action :authorize_admin!
    before_action :set_project, only: [ :show, :add_member, :remove_member ]

    def index
      @projects = Project.order(:name)
    end

    def show
      @user_roles = @project.user_roles.includes(:user, :role).order("roles.sort_order")
      @project_memberships = @project.project_memberships.order(:role, :user_name)
      @available_users = User.active.order(:email)
      @available_roles = Role.where(scope: "project").sorted
    end

    def add_member
      user = User.find(params[:user_id])
      role = Role.find(params[:role_id])

      user_role = @project.user_roles.build(user: user, role: role)

      if user_role.save
        audit_log("project_member_added", subject: @project,
          metadata: {
            project_id: @project.id,
            target_user_id: user.id,
            target_email: user.email,
            role_name: role.name
          })
        redirect_to admin_project_path(@project), success: "#{user.display_label} assigned as #{role.display_name}."
      else
        redirect_to admin_project_path(@project), error: user_role.errors.full_messages.to_sentence
      end
    end

    def remove_member
      user_role = @project.user_roles.find(params[:user_role_id])
      user = user_role.user
      role = user_role.role

      audit_log("project_member_removed", subject: @project,
        metadata: {
          project_id: @project.id,
          target_user_id: user.id,
          target_email: user.email,
          role_name: role.name
        })
      user_role.destroy!
      redirect_to admin_project_path(@project), success: "#{user.display_label} removed from #{role.display_name}."
    end

    private

    def set_project
      @project = Project.find(params[:id])
    end
  end
end
