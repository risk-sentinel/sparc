class SspDocumentsController < ApplicationController
  include FileUploadable

  before_action :set_ssp_document, only: [
    :show, :edit, :update, :destroy,
    :download_json, :download_oscal, :download_oscal_validated, :download_oscal_unvalidated,
    :download_yaml, :download_xml,
    :status, :update_metadata, :enrich, :update_enrich
  ]

  def index
    @ssp_documents = SspDocument.order(created_at: :desc)
    @total_count = @ssp_documents.count
    @controls_count = SspControl.count
    @completed_count = @ssp_documents.where(status: "completed").count
  end

  def show
    # Short-circuit for documents still being processed
    return if @ssp_document.pending? || @ssp_document.processing? || @ssp_document.failed?

    # Load root controls only; provider statements eagerly loaded via association
    @controls = @ssp_document.ssp_controls
                              .roots
                              .includes(:ssp_control_fields,
                                        ssp_by_components: :ssp_component,
                                        provider_statements: :ssp_control_fields)

    # OSCAL entity panels (always load regardless of creation_method)
    @components      = @ssp_document.ssp_components.order(:title)
    @users           = @ssp_document.ssp_users.order(:title)
    @info_types      = @ssp_document.ssp_information_types.order(:title)
    @leveraged_auths = @ssp_document.ssp_leveraged_authorizations.order(:title)

    # Build a catalog-guidance lookup keyed by normalized control_id.
    # Normalisation (AC-1 -> AC-01) bridges documents that use unpadded IDs
    # against the catalog which stores zero-padded IDs.
    normalized_ids = @controls.map { normalize_ctrl_id(_1.control_id) }.compact.uniq
    @catalog_guidance = CatalogControl
                          .where(control_id: normalized_ids)
                          .index_by(&:control_id)

    # Heatmap uses root controls; status field is now 'status'
    @heatmap_data, @heatmap_families, @heatmap_statuses =
      build_heatmap(@controls, "status")
  end

  def new
    @ssp_document = SspDocument.new
  end

  def editor
    # Renders the integrated editor view
  end

  def create
    handle_file_upload(:ssp, param_key: :ssp_document)
  end

  def edit
    @control = @ssp_document.ssp_controls
                             .includes(:ssp_control_fields)
                             .find(params[:control_id]) if params[:control_id]
  end

  def update
    update_service = SspUpdateService.new(@ssp_document)

    begin
      if params[:bulk_update]
        update_service.bulk_update(params[:controls])
        flash[:success] = "Controls updated successfully"
      else
        update_service.update_control(params[:control_id], params[:fields])
        flash[:success] = "Control updated successfully"
      end

      audit_log("ssp_document_updated", subject: @ssp_document,
        metadata: { name: @ssp_document.name, bulk: params[:bulk_update].present? })
      redirect_to @ssp_document
    rescue StandardError => e
      flash[:error] = "Error updating: #{e.message}"
      redirect_to edit_ssp_document_path(@ssp_document)
    end
  end

  # ── Wizard (create SSP from scratch) ─────────────────────────────

  def wizard
    @ssp_document = SspDocument.new
    @profiles = ProfileDocument.where(status: "completed").order(:name)
    @cdefs    = CdefDocument.where(status: "completed").order(:name)
  end

  def create_from_wizard
    service = SspWizardService.new(wizard_params)
    document = service.create

    audit_log("ssp_document_created", subject: document,
      metadata: { name: document.name, creation_method: "wizard" })
    flash[:success] = "SSP '#{document.name}' created from wizard."
    redirect_to ssp_document_path(document)
  rescue StandardError => e
    flash[:error] = "Error creating SSP: #{e.message}"
    redirect_to wizard_ssp_documents_path
  end

  # ── Enrichment (uplift legacy SSPs) ──────────────────────────────

  def enrich
    @components  = @ssp_document.ssp_components.order(:title)
    @users       = @ssp_document.ssp_users.order(:title)
    @info_types  = @ssp_document.ssp_information_types.order(:title)
  end

  def update_enrich
    ActiveRecord::Base.transaction do
      @ssp_document.update!(enrich_params)
      sync_information_types
      sync_components
      sync_users
    end

    audit_log("ssp_document_updated", subject: @ssp_document,
      metadata: { name: @ssp_document.name, enrichment: true })
    flash[:success] = "SSP enrichment data saved."
    redirect_to ssp_document_path(@ssp_document)
  rescue StandardError => e
    flash[:error] = "Error saving enrichment: #{e.message}"
    redirect_to enrich_ssp_document_path(@ssp_document)
  end

  # ── Downloads ────────────────────────────────────────────────────

  def download_json
    json_data = JsonExportService.export_ssp(@ssp_document)

    audit_log("ssp_document_exported", subject: @ssp_document,
      metadata: { name: @ssp_document.name, format: "json" })

    send_data json_data,
              filename:    "#{@ssp_document.name}_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_oscal
    service = OscalSspExportService.new(@ssp_document)
    result = service.validation_result

    if result.valid?
      audit_log("ssp_document_exported", subject: @ssp_document,
        metadata: { name: @ssp_document.name, format: "oscal" })
      send_data service.export,
                filename:    "#{@ssp_document.name}_oscal_ssp_#{Date.today}.json",
                type:        "application/json",
                disposition: "attachment"
    else
      Rails.logger.warn("OSCAL validation failed for SSP #{@ssp_document.id}: #{result.errors.first(3).join('; ')}")
      flash[:warning] = "OSCAL export failed schema validation. Use the unvalidated download instead."
      redirect_to ssp_document_path(@ssp_document)
    end
  end

  def download_oscal_validated
    service = OscalSspExportService.new(@ssp_document)
    oscal_data = service.export

    audit_log("ssp_document_exported", subject: @ssp_document,
      metadata: { name: @ssp_document.name, format: "oscal_validated" })

    send_data oscal_data,
              filename:    "#{@ssp_document.name}_oscal_ssp_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_oscal_unvalidated
    service = OscalSspExportService.new(@ssp_document)
    oscal_data = service.export_unvalidated

    audit_log("ssp_document_exported", subject: @ssp_document,
      metadata: { name: @ssp_document.name, format: "oscal_unvalidated" })

    send_data oscal_data,
              filename:    "#{@ssp_document.name}_oscal_ssp_unvalidated_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_yaml
    json_string = OscalSspExportService.new(@ssp_document).export
    yaml_data = OscalExportFormatService.to_yaml(json_string)

    audit_log("ssp_document_exported", subject: @ssp_document,
      metadata: { name: @ssp_document.name, format: "yaml" })

    send_data yaml_data,
              filename:    "#{@ssp_document.name}_oscal_ssp_#{Date.today}.yaml",
              type:        "application/x-yaml",
              disposition: "attachment"
  end

  def download_xml
    json_string = OscalSspExportService.new(@ssp_document).export
    xml_data = OscalExportFormatService.to_xml(json_string, :ssp)

    audit_log("ssp_document_exported", subject: @ssp_document,
      metadata: { name: @ssp_document.name, format: "xml" })

    send_data xml_data,
              filename:    "#{@ssp_document.name}_oscal_ssp_#{Date.today}.xml",
              type:        "application/xml",
              disposition: "attachment"
  end

  def update_metadata
    if @ssp_document.update(document_metadata_params)
      audit_log("ssp_document_updated", subject: @ssp_document,
        metadata: { name: @ssp_document.name, metadata_update: true })
      flash[:success] = "Document updated"
    else
      flash[:error] = @ssp_document.errors.full_messages.join(", ")
    end
    redirect_to ssp_document_path(@ssp_document)
  end

  def status
    render json: {
      status: @ssp_document.status,
      error_message: @ssp_document.error_message
    }
  end

  def destroy
    name = @ssp_document.name
    if @ssp_document.destroy
      audit_log("ssp_document_deleted", subject: @ssp_document, metadata: { name: name })
      flash[:success] = "SSP '#{name}' deleted."
      redirect_to ssp_documents_path
    else
      audit_log("ssp_document_delete_blocked", subject: @ssp_document,
        metadata: { name: name, reason: @ssp_document.errors.full_messages.join(", ") })
      flash[:error] = @ssp_document.errors.full_messages.join(", ")
      redirect_to ssp_document_path(@ssp_document)
    end
  end

  private

  def document_metadata_params
    permitted = params.require(:ssp_document).permit(:name, :ssp_version, :oscal_version, :description)
    merge_metadata_extra(permitted, :ssp_document)
  end

  def wizard_params
    params.permit(
      :name, :description, :profile_document_id,
      :system_status, :security_sensitivity_level,
      :security_objective_confidentiality,
      :security_objective_integrity,
      :security_objective_availability,
      :authorization_boundary_description,
      cdef_document_ids: []
    )
  end

  def enrich_params
    params.require(:ssp_document).permit(
      :description, :system_name_short, :system_id,
      :system_status, :date_authorized,
      :security_sensitivity_level,
      :security_objective_confidentiality,
      :security_objective_integrity,
      :security_objective_availability,
      :authorization_boundary_description,
      :network_architecture_description,
      :data_flow_description
    )
  end

  def set_ssp_document
    @ssp_document = SspDocument.find_by!(slug: params[:id])
  end

  # ── Enrichment sync helpers ──────────────────────────────────────

  def sync_information_types
    incoming = params.dig(:ssp_document, :information_types) || []
    existing_ids = @ssp_document.ssp_information_types.pluck(:id)
    seen_ids = []

    incoming.each do |it_params|
      it_params = it_params.permit(:id, :title, :description,
                                   :confidentiality_impact_base, :integrity_impact_base,
                                   :availability_impact_base)
      if it_params[:id].present? && existing_ids.include?(it_params[:id].to_i)
        record = @ssp_document.ssp_information_types.find(it_params[:id])
        record.update!(it_params.except(:id))
        seen_ids << record.id
      else
        record = @ssp_document.ssp_information_types.create!(
          uuid: SecureRandom.uuid,
          title: it_params[:title] || "Information Type",
          description: it_params[:description] || "No description provided.",
          confidentiality_impact_base: it_params[:confidentiality_impact_base],
          integrity_impact_base: it_params[:integrity_impact_base],
          availability_impact_base: it_params[:availability_impact_base]
        )
        seen_ids << record.id
      end
    end

    @ssp_document.ssp_information_types.where.not(id: seen_ids).delete_all
  end

  def sync_components
    incoming = params.dig(:ssp_document, :components) || []
    existing_ids = @ssp_document.ssp_components.pluck(:id)
    seen_ids = []

    incoming.each do |c_params|
      c_params = c_params.permit(:id, :component_type, :title, :description, :status_state)
      if c_params[:id].present? && existing_ids.include?(c_params[:id].to_i)
        record = @ssp_document.ssp_components.find(c_params[:id])
        record.update!(c_params.except(:id))
        seen_ids << record.id
      else
        record = @ssp_document.ssp_components.create!(
          uuid: SecureRandom.uuid,
          component_type: c_params[:component_type] || "software",
          title: c_params[:title] || "Component",
          description: c_params[:description] || "No description provided.",
          status_state: c_params[:status_state] || "operational"
        )
        seen_ids << record.id
      end
    end

    # Preserve "this-system" components that aren't in the form
    protected_ids = @ssp_document.ssp_components.this_system.pluck(:id)
    @ssp_document.ssp_components.where.not(id: seen_ids + protected_ids).delete_all
  end

  def sync_users
    incoming = params.dig(:ssp_document, :users) || []
    existing_ids = @ssp_document.ssp_users.pluck(:id)
    seen_ids = []

    incoming.each do |u_params|
      u_params = u_params.permit(:id, :title, :description, :short_name, role_ids_data: [])
      if u_params[:id].present? && existing_ids.include?(u_params[:id].to_i)
        record = @ssp_document.ssp_users.find(u_params[:id])
        record.update!(u_params.except(:id))
        seen_ids << record.id
      else
        record = @ssp_document.ssp_users.create!(
          uuid: SecureRandom.uuid,
          title: u_params[:title],
          description: u_params[:description],
          short_name: u_params[:short_name],
          role_ids_data: u_params[:role_ids_data] || []
        )
        seen_ids << record.id
      end
    end

    @ssp_document.ssp_users.where.not(id: seen_ids).delete_all
  end

  # ── Heatmap ──────────────────────────────────────────────────────

  SSP_STATUS_ORDER = [
    "Implemented", "Deferred", "Not Applicable", "Will Not Implement",
    # Legacy values -- kept so old data sorts predictably
    "Partially Implemented", "Planned", "Alternative Implementation", "Not Implemented"
  ].freeze

  def build_heatmap(controls, status_field_name)
    data = {}
    controls.each do |control|
      next if control.control_id.blank?
      family      = control.control_id.to_s.split("-").first.upcase
      status_field = control.ssp_control_fields.find { |f| f.field_name == status_field_name }
      status       = status_field&.field_value.presence || "(Unknown)"

      data[family]         ||= {}
      data[family][status] ||= 0
      data[family][status]  += 1
    end

    families    = data.keys.sort
    all_statuses = data.values.flat_map(&:keys).uniq
    ordered      = SSP_STATUS_ORDER.select { |s| all_statuses.include?(s) }
    ordered     += (all_statuses - SSP_STATUS_ORDER).sort
    [ data, families, ordered ]
  end
end
