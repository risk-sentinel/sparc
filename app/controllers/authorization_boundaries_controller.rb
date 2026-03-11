class AuthorizationBoundariesController < ApplicationController
  before_action :set_authorization_boundary, only: [ :show, :edit, :update, :destroy ]

  def index
    @authorization_boundaries = AuthorizationBoundary.order(updated_at: :desc)
    @total_count = @authorization_boundaries.count
    @active_count = @authorization_boundaries.where(status: "active").count
    @member_count = AuthorizationBoundaryMembership.count
  end

  def show
    @boundaries  = @authorization_boundary.boundaries.includes(:cdef_documents).order(:name)
    @memberships = @authorization_boundary.authorization_boundary_memberships.order(:role, :user_name)
    @summary     = @authorization_boundary.artifact_summary
  end

  def new
    @authorization_boundary = AuthorizationBoundary.new
  end

  def create
    @authorization_boundary = AuthorizationBoundary.new(authorization_boundary_params)

    if @authorization_boundary.save
      audit_log("authorization_boundary_created", subject: @authorization_boundary, metadata: { name: @authorization_boundary.name })
      flash[:success] = "Authorization boundary '#{@authorization_boundary.name}' created."
      redirect_to @authorization_boundary
    else
      flash.now[:error] = @authorization_boundary.errors.full_messages.join(", ")
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @authorization_boundary.update(authorization_boundary_params)
      audit_log("authorization_boundary_updated", subject: @authorization_boundary, metadata: { name: @authorization_boundary.name })
      flash[:success] = "Authorization boundary updated."
      redirect_to @authorization_boundary
    else
      flash.now[:error] = @authorization_boundary.errors.full_messages.join(", ")
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @authorization_boundary.name
    audit_log("authorization_boundary_deleted", subject: @authorization_boundary, metadata: { name: name })
    @authorization_boundary.destroy
    flash[:success] = "Authorization boundary '#{name}' deleted."
    redirect_to authorization_boundaries_path
  end

  private

  def set_authorization_boundary
    @authorization_boundary = AuthorizationBoundary.find(params[:id])
  end

  def authorization_boundary_params
    params.require(:authorization_boundary).permit(:name, :description, :status, :authorization_boundary_description)
  end
end
