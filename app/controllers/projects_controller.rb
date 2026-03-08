class ProjectsController < ApplicationController
  before_action :set_project, only: [ :show, :edit, :update, :destroy ]

  def index
    @projects = Project.order(updated_at: :desc)
    @total_count = @projects.count
    @active_count = @projects.where(status: "active").count
    @member_count = ProjectMembership.count
  end

  def show
    @boundaries  = @project.boundaries.includes(:cdef_documents).order(:name)
    @memberships = @project.project_memberships.order(:role, :user_name)
    @summary     = @project.artifact_summary
  end

  def new
    @project = Project.new
  end

  def create
    @project = Project.new(project_params)

    if @project.save
      flash[:success] = "Project '#{@project.name}' created."
      redirect_to @project
    else
      flash.now[:error] = @project.errors.full_messages.join(", ")
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @project.update(project_params)
      flash[:success] = "Project updated."
      redirect_to @project
    else
      flash.now[:error] = @project.errors.full_messages.join(", ")
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @project.destroy
    flash[:success] = "Project '#{@project.name}' deleted."
    redirect_to projects_path
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.require(:project).permit(:name, :description, :status, :authorization_boundary_description)
  end
end
