class BoundariesController < ApplicationController
  before_action :set_project
  before_action :set_boundary, only: [ :edit, :update, :destroy ]

  def new
    @boundary = @project.boundaries.new
    @cdef_documents = CdefDocument.where(status: "completed").order(:name)
  end

  def create
    @boundary = @project.boundaries.new(boundary_params)

    if @boundary.save
      sync_cdef_documents
      audit_log("boundary_created", subject: @boundary, metadata: { name: @boundary.name, project_id: @project.id })
      flash[:success] = "Boundary '#{@boundary.name}' created."
      redirect_to @project
    else
      @cdef_documents = CdefDocument.where(status: "completed").order(:name)
      flash.now[:error] = @boundary.errors.full_messages.join(", ")
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @cdef_documents = CdefDocument.where(status: "completed").order(:name)
  end

  def update
    if @boundary.update(boundary_params)
      sync_cdef_documents
      audit_log("boundary_updated", subject: @boundary, metadata: { name: @boundary.name })
      flash[:success] = "Boundary updated."
      redirect_to @project
    else
      @cdef_documents = CdefDocument.where(status: "completed").order(:name)
      flash.now[:error] = @boundary.errors.full_messages.join(", ")
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @boundary.name
    audit_log("boundary_deleted", subject: @boundary, metadata: { name: name })
    @boundary.destroy
    flash[:success] = "Boundary deleted."
    redirect_to @project
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_boundary
    @boundary = @project.boundaries.find(params[:id])
  end

  def boundary_params
    params.require(:boundary).permit(:name, :description, :environment)
  end

  def sync_cdef_documents
    incoming_ids = Array(params.dig(:boundary, :cdef_document_ids)).reject(&:blank?).map(&:to_i)
    @boundary.cdef_document_ids = incoming_ids
  end
end
