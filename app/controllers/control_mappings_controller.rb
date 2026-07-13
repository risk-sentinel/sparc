# frozen_string_literal: true

class ControlMappingsController < ApplicationController
  # #726: index/show join the Controls layer public-read gate
  # (SPARC_PUBLIC_CATALOGS, secure-by-default). (AC-3)
  skip_before_action :require_authentication, only: [ :index, :show ]
  before_action :require_authentication_unless_public_controls, only: [ :index, :show ]
  before_action :authorize_mapping_write!, only: [
    :new, :create, :edit, :update, :destroy, :publish, :deprecate
  ]
  before_action :set_control_mapping, only: [
    :show, :edit, :update, :destroy, :publish, :deprecate, :download_oscal
  ]

  def index
    @control_mappings = ControlMapping.sorted.includes(:source_catalog, :target_catalog)
    @total_count      = @control_mappings.size
    @complete_count   = @control_mappings.count { |m| m.status == "complete" }
    @draft_count      = @control_mappings.count { |m| m.status == "draft" }
  end

  def show
    @entries = @control_mapping.control_mapping_entries.includes(:control_mapping)
    @entry   = ControlMappingEntry.new
  end

  def new
    @control_mapping = ControlMapping.new
    load_catalogs
  end

  def create
    @control_mapping = ControlMapping.new(control_mapping_params)

    if @control_mapping.save
      audit_log("control_mapping_created", subject: @control_mapping, metadata: { name: @control_mapping.name })
      redirect_to @control_mapping, flash: { success: "Control mapping created." }
    else
      load_catalogs
      flash.now[:error] = "Failed to create control mapping."
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_catalogs
  end

  def update
    if @control_mapping.update(control_mapping_params)
      audit_log("control_mapping_updated", subject: @control_mapping, metadata: { name: @control_mapping.name })
      redirect_to @control_mapping, flash: { success: "Control mapping updated." }
    else
      load_catalogs
      flash.now[:error] = "Failed to update control mapping."
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @control_mapping.name
    audit_log("control_mapping_deleted", subject: @control_mapping, metadata: { name: name })
    @control_mapping.destroy
    redirect_to control_mappings_path, flash: { success: "Control mapping '#{name}' deleted." }
  end

  # PATCH /control_mappings/:id/publish
  def publish
    @control_mapping.update!(status: "complete")
    audit_log("control_mapping_published", subject: @control_mapping, metadata: { name: @control_mapping.name })
    redirect_to @control_mapping, flash: { success: "Control mapping published." }
  end

  # PATCH /control_mappings/:id/deprecate
  def deprecate
    @control_mapping.update!(status: "deprecated")
    audit_log("control_mapping_deprecated", subject: @control_mapping, metadata: { name: @control_mapping.name })
    redirect_to @control_mapping, flash: { success: "Control mapping deprecated." }
  end

  # GET /control_mappings/:id/download_oscal
  def download_oscal
    service = OscalMappingExportService.new(@control_mapping)
    json_data = service.export_unvalidated

    audit_log("control_mapping_exported", subject: @control_mapping, metadata: { name: @control_mapping.name, format: "oscal" })
    send_data json_data,
              filename: "#{@control_mapping.name.parameterize}_mapping_#{Date.today}.json",
              type: "application/json",
              disposition: "attachment"
  end

  private

  def set_control_mapping
    @control_mapping = ControlMapping.find_by!(slug: params[:id])
  end

  def load_catalogs
    @catalogs = ControlCatalog.order(:name)
  end

  def control_mapping_params
    params.require(:control_mapping).permit(
      :name, :description, :mapping_version, :oscal_version,
      :status, :method_type, :matching_rationale,
      :source_catalog_id, :target_catalog_id
    )
  end

  def authorize_mapping_write!
    authorize_permission!("mappings.write")
  end
end
