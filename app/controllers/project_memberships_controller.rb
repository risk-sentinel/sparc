class ProjectMembershipsController < ApplicationController
  before_action :set_project
  before_action :set_membership, only: [ :edit, :update, :destroy ]

  def new
    @membership = @project.project_memberships.new
  end

  def create
    @membership = @project.project_memberships.new(membership_params)

    if @membership.save
      audit_log("project_membership_created", subject: @membership, metadata: { project_id: @project.id, user_name: @membership.user_name })
      flash[:success] = "Member '#{@membership.user_name}' added as #{@membership.role_label}."
      redirect_to @project
    else
      flash.now[:error] = @membership.errors.full_messages.join(", ")
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @membership.update(membership_params)
      audit_log("project_membership_updated", subject: @membership, metadata: { project_id: @project.id })
      flash[:success] = "Membership updated."
      redirect_to @project
    else
      flash.now[:error] = @membership.errors.full_messages.join(", ")
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    audit_log("project_membership_deleted", subject: @membership, metadata: { project_id: @project.id })
    @membership.destroy
    flash[:success] = "Member removed."
    redirect_to @project
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_membership
    @membership = @project.project_memberships.find(params[:id])
  end

  def membership_params
    permitted = params.require(:project_membership).permit(:user_name, :user_email)
    role = params.dig(:project_membership, :role)
    permitted[:role] = role if role.present? && ProjectMembership::ROLES.include?(role)
    permitted
  end
end
