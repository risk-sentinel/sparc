class SspDocumentsController < ApplicationController
  include FileUploadable

  before_action :set_ssp_document, only: [ :show, :edit, :update, :destroy, :download_json, :download_oscal, :status ]

  def index
    @ssp_documents = SspDocument.order(created_at: :desc)
  end

  def show
    # Short-circuit for documents still being processed
    return if @ssp_document.pending? || @ssp_document.processing? || @ssp_document.failed?

    # Load root controls only; provider statements eagerly loaded via association
    @controls = @ssp_document.ssp_controls
                              .roots
                              .includes(:ssp_control_fields,
                                        provider_statements: :ssp_control_fields)

    # Build a catalog-guidance lookup keyed by normalized control_id.
    # Normalisation (AC-1 → AC-01) bridges documents that use unpadded IDs
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

      redirect_to @ssp_document
    rescue StandardError => e
      flash[:error] = "Error updating: #{e.message}"
      redirect_to edit_ssp_document_path(@ssp_document)
    end
  end

  def download_json
    json_data = JsonExportService.export_ssp(@ssp_document)

    send_data json_data,
              filename:    "#{@ssp_document.name}_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_oscal
    service = OscalSspExportService.new(@ssp_document)
    oscal_data = service.export

    send_data oscal_data,
              filename:    "#{@ssp_document.name}_oscal_ssp_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  rescue OscalValidationError => e
    Rails.logger.warn("OSCAL validation failed for SSP #{@ssp_document.id}: #{e.message}")
    flash[:error] = "OSCAL export failed schema validation. Downloading unvalidated version."
    oscal_data = service.export_unvalidated
    send_data oscal_data,
              filename:    "#{@ssp_document.name}_oscal_ssp_unvalidated_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def status
    render json: {
      status: @ssp_document.status,
      error_message: @ssp_document.error_message
    }
  end

  def destroy
    @ssp_document.destroy
    flash[:success] = "Controls Implementation document deleted"
    redirect_to ssp_documents_path
  end

  private

  def set_ssp_document
    @ssp_document = SspDocument.find(params[:id])
  end

  SSP_STATUS_ORDER = [
    "Implemented", "Deferred", "Not Applicable", "Will Not Implement",
    # Legacy values — kept so old data sorts predictably
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
