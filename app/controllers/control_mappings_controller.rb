# frozen_string_literal: true

class ControlMappingsController < ApplicationController
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
      log_audit("control_mapping_created", "Created control mapping '#{@control_mapping.name}'")
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
      log_audit("control_mapping_updated", "Updated control mapping '#{@control_mapping.name}'")
      redirect_to @control_mapping, flash: { success: "Control mapping updated." }
    else
      load_catalogs
      flash.now[:error] = "Failed to update control mapping."
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @control_mapping.name
    @control_mapping.destroy
    log_audit("control_mapping_deleted", "Deleted control mapping '#{name}'")
    redirect_to control_mappings_path, flash: { success: "Control mapping '#{name}' deleted." }
  end

  # PATCH /control_mappings/:id/publish
  def publish
    @control_mapping.update!(status: "complete")
    log_audit("control_mapping_published", "Published control mapping '#{@control_mapping.name}'")
    redirect_to @control_mapping, flash: { success: "Control mapping published." }
  end

  # PATCH /control_mappings/:id/deprecate
  def deprecate
    @control_mapping.update!(status: "deprecated")
    log_audit("control_mapping_deprecated", "Deprecated control mapping '#{@control_mapping.name}'")
    redirect_to @control_mapping, flash: { success: "Control mapping deprecated." }
  end

  # GET /control_mappings/:id/download_oscal
  def download_oscal
    service = OscalMappingExportService.new(@control_mapping)
    json_data = service.export_unvalidated

    send_data json_data,
              filename: "#{@control_mapping.name.parameterize}_mapping_#{Date.today}.json",
              type: "application/json",
              disposition: "attachment"
  end

  private

  def set_control_mapping
    @control_mapping = ControlMapping.find(params[:id])
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

  def log_audit(action, message)
    return unless defined?(AuditEvent) && current_user

    AuditEvent.log(
      user: current_user,
      action: action,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      metadata: { control_mapping_id: @control_mapping&.id, message: message }
    )
  end
end
