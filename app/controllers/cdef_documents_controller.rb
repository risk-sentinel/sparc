class CdefDocumentsController < ApplicationController
  include FileUploadable
  include Publishable
  include OscalExportable
  skip_before_action :require_authentication, only: [ :index, :show ]

  before_action :set_cdef_document, only: %i[show destroy download_json download_oscal download_oscal_validated download_oscal_unvalidated download_yaml download_xml validate_oscal_export status update_metadata update_field copy publish publish_check create_control_resource link_control_resource unlink_control_resource]
  before_action :ensure_editable!, only: [ :update_metadata, :update_field, :publish, :create_control_resource, :link_control_resource, :unlink_control_resource ]

  SEVERITY_ORDER = %w[high medium low info].freeze

  def index
    @cdef_documents = CdefDocument.order(created_at: :desc)
    @total_count = @cdef_documents.count
    @controls_count = CdefControl.count
    @completed_count = @cdef_documents.where(status: "completed").count
  end

  def show
    return if @cdef_document.pending? || @cdef_document.processing? || @cdef_document.failed?

    controls_scope = @cdef_document.cdef_controls

    @severity_counts = controls_scope.group(:severity).count
    @total_controls  = controls_scope.count

    @heatmap_data, @heatmap_families, @heatmap_severities = build_severity_heatmap(controls_scope)

    @controls = controls_scope.order(:row_order).includes(:cdef_control_fields)

    # Baseline gap analysis (when CDEF was created from a profile)
    if @cdef_document.profile_document.present?
      gap_service = CdefBaselineGapService.new(@cdef_document)
      @gap_analysis = gap_service.analyze
      @missing_controls = gap_service.missing_control_details if @gap_analysis&.dig(:missing)&.any?
    end
  end

  def new
    @cdef_document = CdefDocument.new
  end

  def create
    handle_multi_file_upload(:cdef, param_key: :cdef_document)
  end

  def destroy
    name = @cdef_document.name
    if @cdef_document.destroy
      audit_log("cdef_document_deleted", subject: @cdef_document, metadata: { name: name })
      flash[:success] = "Component Definition '#{name}' deleted."
      redirect_to cdef_documents_path
    else
      audit_log("cdef_document_delete_blocked", subject: @cdef_document,
        metadata: { name: name, reason: @cdef_document.errors.full_messages.join(", ") })
      flash[:error] = @cdef_document.errors.full_messages.join(", ")
      redirect_to cdef_document_path(@cdef_document)
    end
  end

  def download_json
    json_data = JsonExportService.export_cdef(@cdef_document)

    audit_log("cdef_document_exported", subject: @cdef_document, metadata: { name: @cdef_document.name, format: "json" })
    send_data json_data,
              filename:    "#{@cdef_document.name}_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_oscal
    service = OscalComponentDefinitionExportService.new(@cdef_document)
    result = service.validation_result

    if result.valid?
      audit_log("cdef_document_exported", subject: @cdef_document, metadata: { name: @cdef_document.name, format: "oscal" })
      send_data service.export,
                filename:    "#{@cdef_document.name}_oscal_cdef_#{Date.today}.json",
                type:        "application/json",
                disposition: "attachment"
    else
      Rails.logger.warn("OSCAL validation failed for CDEF #{@cdef_document.id}: #{result.errors.first(3).join('; ')}")
      flash[:warning] = "OSCAL export failed schema validation. Use the unvalidated download instead."
      redirect_to cdef_document_path(@cdef_document)
    end
  end

  def download_oscal_validated
    service = OscalComponentDefinitionExportService.new(@cdef_document)
    oscal_data = service.export

    audit_log("cdef_document_exported", subject: @cdef_document, metadata: { name: @cdef_document.name, format: "oscal_validated" })
    send_data oscal_data,
              filename:    "#{@cdef_document.name}_oscal_component_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_oscal_unvalidated
    service = OscalComponentDefinitionExportService.new(@cdef_document)
    oscal_data = service.export_unvalidated

    audit_log("cdef_document_exported", subject: @cdef_document, metadata: { name: @cdef_document.name, format: "oscal_unvalidated" })
    send_data oscal_data,
              filename:    "#{@cdef_document.name}_oscal_component_unvalidated_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_yaml
    service = OscalComponentDefinitionExportService.new(@cdef_document)
    json_string = params[:skip_validation] ? service.export_unvalidated : service.export
    yaml_data = OscalExportFormatService.to_yaml(json_string)

    audit_log("cdef_document_exported", subject: @cdef_document, metadata: { name: @cdef_document.name, format: "yaml" })
    send_data yaml_data,
              filename:    "#{@cdef_document.name}_oscal_cdef_#{Date.today}.yaml",
              type:        "application/x-yaml",
              disposition: "attachment"
  end

  def download_xml
    service = OscalComponentDefinitionExportService.new(@cdef_document)
    json_string = params[:skip_validation] ? service.export_unvalidated : service.export
    xml_data = OscalExportFormatService.to_xml(json_string, :component_definition)

    audit_log("cdef_document_exported", subject: @cdef_document, metadata: { name: @cdef_document.name, format: "xml" })
    send_data xml_data,
              filename:    "#{@cdef_document.name}_oscal_cdef_#{Date.today}.xml",
              type:        "application/xml",
              disposition: "attachment"
  end

  def update_field
    control_id = params[:control_id]
    field_name = params[:field_name]
    field_value = params[:field_value]

    service = CdefUpdateService.new(@cdef_document)
    service.update_field(control_id, field_name, field_value)

    audit_log("cdef_control_updated", subject: @cdef_document,
      metadata: { control_id: control_id, field_name: field_name })

    respond_to do |format|
      format.json { render json: { success: true, control_id: control_id, field_name: field_name, field_value: field_value } }
      format.html do
        flash[:success] = "#{field_name.titleize} updated for #{control_id}"
        redirect_to cdef_document_path(@cdef_document, anchor: "control-#{control_id}")
      end
    end
  rescue ArgumentError, ActiveRecord::RecordNotFound => e
    respond_to do |format|
      format.json { render json: { success: false, error: e.message }, status: :unprocessable_entity }
      format.html do
        flash[:error] = e.message
        redirect_to cdef_document_path(@cdef_document)
      end
    end
  end

  def update_metadata
    if @cdef_document.update(document_metadata_params)
      @cdef_document.regenerate_oscal_uuid!
      audit_log("cdef_document_updated", subject: @cdef_document, metadata: { name: @cdef_document.name, metadata_update: true })
      flash[:success] = "Document updated"
    else
      flash[:error] = @cdef_document.errors.full_messages.join(", ")
    end
    redirect_to cdef_document_path(@cdef_document)
  end

  def copy
    service = DocumentDuplicationService.new(@cdef_document)
    copy = service.duplicate

    audit_log("cdef_document_copied", subject: copy, metadata: { source_id: @cdef_document.id, source_name: @cdef_document.name, copy_name: copy.name })
    flash[:success] = "Component Definition duplicated as '#{copy.name}'"
    redirect_to cdef_document_path(copy)
  end

  def select_profile
    @profiles = ProfileDocument.where(lifecycle_status: "published")
                               .where.not(resolved_catalog_json: nil)
                               .includes(:control_catalog)
                               .order(updated_at: :desc)
  end

  def create_from_profile
    profile = ProfileDocument.find_by!(slug: params[:source_profile_id])

    cdef = CdefFromProfileService.new(profile, name: params[:cdef_name]).create

    audit_log("cdef_document_created_from_profile", subject: cdef,
      metadata: { name: cdef.name, source_profile_id: profile.id, source_profile_name: profile.name })
    flash[:success] = "Component Definition '#{cdef.name}' created from profile '#{profile.name}'."
    redirect_to cdef_document_path(cdef)
  rescue ArgumentError => e
    flash[:error] = e.message
    redirect_to select_profile_cdef_documents_path
  rescue ActiveRecord::RecordNotFound
    flash[:error] = "Published profile not found."
    redirect_to select_profile_cdef_documents_path
  end

  def status
    render json: {
      status: @cdef_document.status,
      error_message: @cdef_document.error_message
    }
  end

  # ── Control-level resource linking (AJAX) ───────────────────────────

  def create_control_resource
    control = @cdef_document.cdef_controls.find_by!(control_id: params[:control_id])
    resource = BackMatterResource.new(control_resource_params)
    resource.uuid = SecureRandom.uuid
    resource.source = "managed"
    resource.resourceable = @cdef_document
    resource.organization = current_user.organizations.first if current_user.organizations.any?
    resource.globally_available = params.dig(:back_matter_resource, :globally_available) == "1"

    if resource.save
      control.control_back_matter_links.create!(back_matter_resource: resource)
      audit_log("control_resource_created", subject: resource,
                metadata: { control_id: params[:control_id], title: resource.title })
      render json: { success: true, resource: { id: resource.id, uuid: resource.uuid, title: resource.title, href: resource.href } }
    else
      render json: { success: false, error: resource.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def link_control_resource
    control = @cdef_document.cdef_controls.find_by!(control_id: params[:control_id])
    resource = BackMatterResource.find(params[:back_matter_resource_id])
    link = control.control_back_matter_links.build(back_matter_resource: resource)

    if link.save
      audit_log("control_resource_linked", subject: resource,
                metadata: { control_id: params[:control_id], resource_uuid: resource.uuid })
      render json: { success: true, resource: { id: resource.id, uuid: resource.uuid, title: resource.title } }
    else
      render json: { success: false, error: link.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  def unlink_control_resource
    control = @cdef_document.cdef_controls.find_by!(control_id: params[:control_id])
    link = control.control_back_matter_links.find(params[:link_id])
    audit_log("control_resource_unlinked", subject: link.back_matter_resource,
              metadata: { control_id: params[:control_id] })
    link.destroy
    render json: { success: true }
  end

  private

  def control_resource_params
    params.require(:back_matter_resource).permit(:title, :description, :href, :media_type, :rel)
  end

  def document_metadata_params
    permitted = params.require(:cdef_document).permit(:name, :cdef_version, :oscal_version, :description)
    merge_metadata_extra(permitted, :cdef_document)
  end

  def set_cdef_document
    @cdef_document = CdefDocument.find_by!(slug: params[:id])
  end

  # OscalExportable hooks
  def oscal_export_document = @cdef_document
  def oscal_export_service(doc) = OscalComponentDefinitionExportService.new(doc)
  def oscal_document_type_label = "Component Definition"

  def publish_config
    { document: @cdef_document, audit_event: "cdef_document_published",
      redirect_path: cdef_document_path(@cdef_document), label: "CDEF" }
  end

  def ensure_editable!
    return unless @cdef_document.published_lifecycle?

    flash[:error] = "This component definition is published and read-only. Create a copy to make changes."
    redirect_to cdef_document_path(@cdef_document)
  end

  def build_severity_heatmap(scope)
    rows = scope.where.not(control_family: [ nil, "" ])
                .group(:control_family, :severity).count

    data = {}
    rows.each do |(family, severity), count|
      sev = severity.presence || "(Unknown)"
      data[family] ||= {}
      data[family][sev] = count
    end

    families = data.keys.sort
    all_sevs = data.values.flat_map(&:keys).uniq
    ordered  = SEVERITY_ORDER.select { |s| all_sevs.include?(s) }
    ordered += (all_sevs - SEVERITY_ORDER).sort

    [ data, families, ordered ]
  end
end
