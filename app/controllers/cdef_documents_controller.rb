class CdefDocumentsController < ApplicationController
  include FileUploadable

  before_action :set_cdef_document, only: %i[show destroy download_json download_oscal status]

  SEVERITY_ORDER = %w[high medium low info].freeze

  def index
    @cdef_documents = CdefDocument.order(created_at: :desc)
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
    @cdef_document.destroy
    flash[:success] = "Component Definition deleted"
    redirect_to cdef_documents_path
  end

  def download_json
    json_data = JsonExportService.export_cdef(@cdef_document)

    send_data json_data,
              filename:    "#{@cdef_document.name}_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_oscal
    service = OscalComponentDefinitionExportService.new(@cdef_document)
    oscal_data = service.export

    send_data oscal_data,
              filename:    "#{@cdef_document.name}_oscal_component_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  rescue OscalValidationError => e
    Rails.logger.warn("OSCAL validation failed for CDEF #{@cdef_document.id}: #{e.message}")
    flash[:error] = "OSCAL export failed schema validation. Downloading unvalidated version."
    oscal_data = service.export_unvalidated
    send_data oscal_data,
              filename:    "#{@cdef_document.name}_oscal_component_unvalidated_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def status
    render json: {
      status: @cdef_document.status,
      error_message: @cdef_document.error_message
    }
  end

  private

  def set_cdef_document
    @cdef_document = CdefDocument.find(params[:id])
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
