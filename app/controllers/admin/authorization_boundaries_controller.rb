# frozen_string_literal: true

module Admin
  # Admin interface for managing authorization boundaries — full CRUD plus
  # user role assignments. Restricted to Instance Admins.
  class AuthorizationBoundariesController < ApplicationController
    before_action :authorize_admin!
    before_action :set_authorization_boundary, only: [ :show, :edit, :update, :add_member, :remove_member ]

    def index
      @authorization_boundaries = AuthorizationBoundary.order(:name)
    end

    def show
      @user_roles = @authorization_boundary.user_roles.includes(:user, :role).order("roles.sort_order")
      @authorization_boundary_memberships = @authorization_boundary.authorization_boundary_memberships.order(:role, :user_name)
      @available_users = User.active.order(:email)
      @available_roles = Role.where(scope: "authorization_boundary").sorted
    end

    def new
      @authorization_boundary = AuthorizationBoundary.new
      @organizations = Organization.active.order(:name)
    end

    def create
      @authorization_boundary = AuthorizationBoundary.new(authorization_boundary_params)

      if @authorization_boundary.save
        audit_log("authorization_boundary_created", subject: @authorization_boundary,
          metadata: { name: @authorization_boundary.name })
        redirect_to admin_authorization_boundary_path(@authorization_boundary), success: "Authorization boundary created."
      else
        @organizations = Organization.active.order(:name)
        flash.now[:error] = @authorization_boundary.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @organizations = Organization.active.order(:name)
    end

    def update
      if @authorization_boundary.update(authorization_boundary_params)
        audit_log("authorization_boundary_updated", subject: @authorization_boundary,
          metadata: { name: @authorization_boundary.name })
        redirect_to admin_authorization_boundary_path(@authorization_boundary), success: "Authorization boundary updated."
      else
        @organizations = Organization.active.order(:name)
        flash.now[:error] = @authorization_boundary.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    def add_member
      user = User.find(params[:user_id])
      role = Role.find(params[:role_id])

      user_role = @authorization_boundary.user_roles.build(user: user, role: role)

      if user_role.save
        audit_log("authorization_boundary_member_added", subject: @authorization_boundary,
          metadata: {
            authorization_boundary_id: @authorization_boundary.id,
            target_user_id: user.id,
            target_email: user.email,
            role_name: role.name
          })
        redirect_to admin_authorization_boundary_path(@authorization_boundary), success: "#{user.display_label} assigned as #{role.display_name}."
      else
        redirect_to admin_authorization_boundary_path(@authorization_boundary), error: user_role.errors.full_messages.to_sentence
      end
    end

    def remove_member
      user_role = @authorization_boundary.user_roles.find(params[:user_role_id])
      user = user_role.user
      role = user_role.role

      audit_log("authorization_boundary_member_removed", subject: @authorization_boundary,
        metadata: {
          authorization_boundary_id: @authorization_boundary.id,
          target_user_id: user.id,
          target_email: user.email,
          role_name: role.name
        })
      user_role.destroy!
      redirect_to admin_authorization_boundary_path(@authorization_boundary), success: "#{user.display_label} removed from #{role.display_name}."
    end

    private

    def set_authorization_boundary
      @authorization_boundary = AuthorizationBoundary.find_by!(slug: params[:id])
    end

    def authorization_boundary_params
      params.require(:authorization_boundary).permit(:name, :description, :status, :authorization_boundary_description, :organization_id)
    end
  end
end
