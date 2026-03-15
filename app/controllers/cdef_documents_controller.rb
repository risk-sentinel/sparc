class CdefDocumentsController < ApplicationController
  include FileUploadable
  skip_before_action :require_authentication, only: [ :index, :show ]

  before_action :set_cdef_document, only: %i[show destroy download_json download_oscal download_oscal_validated download_oscal_unvalidated download_yaml download_xml status update_metadata copy]

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
  end

  def new
    @cdef_document = CdefDocument.new
  end

  def create
    handle_file_upload(:cdef, param_key: :cdef_document)
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
    json_string = OscalComponentDefinitionExportService.new(@cdef_document).export
    yaml_data = OscalExportFormatService.to_yaml(json_string)

    audit_log("cdef_document_exported", subject: @cdef_document, metadata: { name: @cdef_document.name, format: "yaml" })
    send_data yaml_data,
              filename:    "#{@cdef_document.name}_oscal_cdef_#{Date.today}.yaml",
              type:        "application/x-yaml",
              disposition: "attachment"
  end

  def download_xml
    json_string = OscalComponentDefinitionExportService.new(@cdef_document).export
    xml_data = OscalExportFormatService.to_xml(json_string, :component_definition)

    audit_log("cdef_document_exported", subject: @cdef_document, metadata: { name: @cdef_document.name, format: "xml" })
    send_data xml_data,
              filename:    "#{@cdef_document.name}_oscal_cdef_#{Date.today}.xml",
              type:        "application/xml",
              disposition: "attachment"
  end

  def update_metadata
    if @cdef_document.update(document_metadata_params)
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

  def status
    render json: {
      status: @cdef_document.status,
      error_message: @cdef_document.error_message
    }
  end

  private

  def document_metadata_params
    permitted = params.require(:cdef_document).permit(:name, :cdef_version, :oscal_version, :description)
    merge_metadata_extra(permitted, :cdef_document)
  end

  def set_cdef_document
    @cdef_document = CdefDocument.find_by!(slug: params[:id])
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
