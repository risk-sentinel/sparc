class AuthorizationBoundaryMembershipsController < ApplicationController
  before_action :set_authorization_boundary
  before_action :set_membership, only: [ :edit, :update, :destroy ]

  def new
    @membership = @authorization_boundary.authorization_boundary_memberships.new
  end

  def create
    @membership = @authorization_boundary.authorization_boundary_memberships.new(membership_params)

    if @membership.save
      audit_log("authorization_boundary_membership_created", subject: @membership, metadata: { authorization_boundary_id: @authorization_boundary.id, user_name: @membership.user_name })
      flash[:success] = "Member '#{@membership.user_name}' added as #{@membership.role_label}."
      redirect_to @authorization_boundary
    else
      flash.now[:error] = @membership.errors.full_messages.join(", ")
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @membership.update(membership_params)
      audit_log("authorization_boundary_membership_updated", subject: @membership, metadata: { authorization_boundary_id: @authorization_boundary.id })
      flash[:success] = "Membership updated."
      redirect_to @authorization_boundary
    else
      flash.now[:error] = @membership.errors.full_messages.join(", ")
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    audit_log("authorization_boundary_membership_deleted", subject: @membership, metadata: { authorization_boundary_id: @authorization_boundary.id })
    @membership.destroy
    flash[:success] = "Member removed."
    redirect_to @authorization_boundary
  end

  private

  def set_authorization_boundary
    @authorization_boundary = AuthorizationBoundary.find(params[:authorization_boundary_id])
  end

  def set_membership
    @membership = @authorization_boundary.authorization_boundary_memberships.find(params[:id])
  end

  def membership_params
    permitted = params.require(:authorization_boundary_membership).permit(:user_name, :user_email)
    role = params.dig(:authorization_boundary_membership, :role)
    permitted[:role] = role if role.present? && AuthorizationBoundaryMembership::ROLES.include?(role)
    permitted
  end
end
