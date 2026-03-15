# frozen_string_literal: true

module Admin
  # Admin interface for managing Organizations with user membership and role assignment.
  # Organizations are never hard-deleted — they are deactivated/reactivated instead,
  # preserving the UUID for audit traceability.
  class OrganizationsController < ApplicationController
    include Pagy::Method

    before_action :authorize_admin!
    before_action :set_organization, only: [ :show, :edit, :update, :deactivate, :reactivate, :add_member, :remove_member ]

    ORGS_PER_PAGE = 25

    def index
      scope = Organization.order(:name)
      if params[:q].present?
        scope = scope.where(
          "name ILIKE :q OR description ILIKE :q OR contact_email ILIKE :q OR contact_person ILIKE :q",
          q: "%#{params[:q]}%"
        )
      end
      scope = scope.where(status: params[:status]) if params[:status].present?
      @pagy, @organizations = pagy(:offset, scope, limit: ORGS_PER_PAGE)
    end

    def show
      @memberships = @organization.organization_memberships.includes(:user).order(:role, "users.email")
      @authorization_boundaries = @organization.authorization_boundaries.order(:name)
      @available_users = User.active.order(:email)
    end

    def new
      @organization = Organization.new
    end

    def create
      @organization = Organization.new(organization_params)

      if @organization.save
        audit_log("organization_created", subject: @organization,
          metadata: { organization_id: @organization.id, name: @organization.name })
        redirect_to admin_organization_path(@organization), success: "Organization created."
      else
        flash.now[:error] = @organization.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @organization.update(organization_params)
        audit_log("organization_updated", subject: @organization,
          metadata: { organization_id: @organization.id, name: @organization.name })
        redirect_to admin_organization_path(@organization), success: "Organization updated."
      else
        flash.now[:error] = @organization.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    def deactivate
      @organization.deactivate!
      audit_log("organization_deactivated", subject: @organization,
        metadata: { organization_id: @organization.id, uuid: @organization.uuid, name: @organization.name })
      redirect_to admin_organization_path(@organization), success: "Organization deactivated."
    end

    def reactivate
      @organization.reactivate!
      audit_log("organization_reactivated", subject: @organization,
        metadata: { organization_id: @organization.id, uuid: @organization.uuid, name: @organization.name })
      redirect_to admin_organization_path(@organization), success: "Organization reactivated."
    end

    def add_member
      user = User.find(params[:user_id])
      membership = @organization.organization_memberships.build(user: user, role: params[:role])

      if membership.save
        audit_log("organization_member_added", subject: @organization,
          metadata: {
            organization_id: @organization.id,
            target_user_id: user.id,
            target_email: user.email,
            role: params[:role]
          })
        redirect_to admin_organization_path(@organization), success: "#{user.display_label} added as #{membership.role_label}."
      else
        redirect_to admin_organization_path(@organization), error: membership.errors.full_messages.to_sentence
      end
    end

    def remove_member
      membership = @organization.organization_memberships.find(params[:membership_id])
      user = membership.user

      audit_log("organization_member_removed", subject: @organization,
        metadata: {
          organization_id: @organization.id,
          target_user_id: user.id,
          target_email: user.email,
          role: membership.role
        })
      membership.destroy!
      redirect_to admin_organization_path(@organization), success: "#{user.display_label} removed from organization."
    end

    private

    def set_organization
      @organization = Organization.find_by!(slug: params[:id])
    end

    def organization_params
      params.require(:organization).permit(:name, :description, :address, :contact_person, :contact_email)
    end
  end
end
