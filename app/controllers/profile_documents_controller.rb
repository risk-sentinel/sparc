class ProfileDocumentsController < ApplicationController
  include FileUploadable

  before_action :set_profile_document, only: %i[
    show destroy download_json download_oscal
    download_oscal_validated download_oscal_unvalidated status
    update_metadata
  ]

  PRIORITY_ORDER = %w[P1 P2 P3].freeze

  def index
    @profile_documents = ProfileDocument.order(created_at: :desc)
  end

  def show
    return if @profile_document.pending? || @profile_document.processing? || @profile_document.failed?

    controls_scope = @profile_document.profile_controls

    @priority_counts = controls_scope.group(:priority).count
    @total_controls  = controls_scope.count

    @heatmap_data, @heatmap_families, @heatmap_priorities = build_priority_heatmap(controls_scope)

    @controls = controls_scope.order(:row_order).includes(:profile_control_fields)
  end

  def new
    @profile_document = ProfileDocument.new
  end

  def create
    handle_file_upload(:profile, param_key: :profile_document)
  end

  def destroy
    @profile_document.destroy
    flash[:success] = "Profile (Baseline) deleted"
    redirect_to profile_documents_path
  end

  def download_json
    json_data = JsonExportService.export_profile(@profile_document)

    send_data json_data,
              filename:    "#{@profile_document.name}_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_oscal
    service = OscalProfileExportService.new(@profile_document)
    result = service.validation_result

    if result.valid?
      download_url = download_oscal_validated_profile_document_path(@profile_document)
      flash[:success] = "OSCAL export passed schema validation (v#{result.schema_version}). <a href=\"#{download_url}\">Download OSCAL file</a>.".html_safe
    else
      Rails.logger.warn("OSCAL validation failed for Profile #{@profile_document.id}: #{result.errors.first(3).join('; ')}")
      download_url = download_oscal_unvalidated_profile_document_path(@profile_document)
      flash[:warning] = "OSCAL export failed schema validation. <a href=\"#{download_url}\">Download unvalidated version</a>.".html_safe
    end

    redirect_to profile_document_path(@profile_document)
  end

  def download_oscal_validated
    service = OscalProfileExportService.new(@profile_document)
    oscal_data = service.export

    send_data oscal_data,
              filename:    "#{@profile_document.name}_oscal_profile_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_oscal_unvalidated
    service = OscalProfileExportService.new(@profile_document)
    oscal_data = service.export_unvalidated

    send_data oscal_data,
              filename:    "#{@profile_document.name}_oscal_profile_unvalidated_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def update_metadata
    if @profile_document.update(document_metadata_params)
      flash[:success] = "Document updated"
    else
      flash[:error] = @profile_document.errors.full_messages.join(", ")
    end
    redirect_to profile_document_path(@profile_document)
  end

  def status
    render json: {
      status: @profile_document.status,
      error_message: @profile_document.error_message
    }
  end

  private

  def document_metadata_params
    params.require(:profile_document).permit(:name, :profile_version)
  end

  def set_profile_document
    @profile_document = ProfileDocument.find(params[:id])
  end

  def build_priority_heatmap(scope)
    rows = scope.where.not(control_family: [ nil, "" ])
                .group(:control_family, :priority).count

    data = {}
    rows.each do |(family, priority), count|
      pri = priority.presence || "(None)"
      data[family] ||= {}
      data[family][pri] = count
    end

    families = data.keys.sort
    all_priorities = data.values.flat_map(&:keys).uniq
    ordered = PRIORITY_ORDER.select { |p| all_priorities.include?(p) }
    ordered += (all_priorities - PRIORITY_ORDER).sort

    [ data, families, ordered ]
  end
end
