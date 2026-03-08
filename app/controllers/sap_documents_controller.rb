class SapDocumentsController < ApplicationController
  include FileUploadable

  before_action :set_sap_document, only: %i[
    show edit update destroy download_json download_oscal
    download_oscal_validated download_oscal_unvalidated status
    update_metadata
  ]

  METHOD_ORDER = %w[examine interview test].freeze

  def index
    @sap_documents = SapDocument.order(created_at: :desc)
  end

  def show
    return if @sap_document.pending? || @sap_document.processing? || @sap_document.failed?

    controls_scope = @sap_document.sap_controls

    @method_counts = controls_scope.group(:assessment_method).count
    @status_counts = controls_scope.group(:assessment_status).count
    @total_controls = controls_scope.count

    @heatmap_data, @heatmap_families, @heatmap_methods = build_method_heatmap(controls_scope)

    @controls = controls_scope.order(:row_order).includes(:sap_control_fields)
  end

  def new
    @sap_document = SapDocument.new
    @ssp_documents = SspDocument.where(status: "completed").order(:name)
    @profile_documents = ProfileDocument.where(status: "completed").order(:name)
  end

  def create
    if params[:sap_document]&.key?(:file) && params[:sap_document][:file].present?
      handle_file_upload(:sap, param_key: :sap_document)
    else
      create_from_wizard
    end
  end

  def edit
    @control = @sap_document.sap_controls.find(params[:control_id]) if params[:control_id]
  end

  def update
    control = @sap_document.sap_controls.find(params[:control_id])
    permitted = params.require(:sap_control).permit(
      :assessment_method, :assessment_status, :assessor_name,
      :objective, :test_case
    )

    if control.update(permitted)
      flash[:success] = "Control #{control.control_id} updated"
    else
      flash[:error] = control.errors.full_messages.join(", ")
    end
    redirect_to sap_document_path(@sap_document)
  end

  def destroy
    @sap_document.destroy
    flash[:success] = "Assessment Plan deleted"
    redirect_to sap_documents_path
  end

  def download_json
    json_data = JsonExportService.export_sap(@sap_document)

    send_data json_data,
              filename:    "#{@sap_document.name}_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_oscal
    service = OscalAssessmentPlanExportService.new(@sap_document)
    result = service.validation_result

    if result.valid?
      send_data service.export,
                filename:    "#{@sap_document.name}_oscal_sap_#{Date.today}.json",
                type:        "application/json",
                disposition: "attachment"
    else
      Rails.logger.warn("OSCAL validation failed for SAP #{@sap_document.id}: #{result.errors.first(3).join('; ')}")
      flash[:warning] = "OSCAL export failed schema validation. Use the unvalidated download instead."
      redirect_to sap_document_path(@sap_document)
    end
  end

  def download_oscal_validated
    service = OscalAssessmentPlanExportService.new(@sap_document)
    oscal_data = service.export

    send_data oscal_data,
              filename:    "#{@sap_document.name}_oscal_assessment-plan_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_oscal_unvalidated
    service = OscalAssessmentPlanExportService.new(@sap_document)
    oscal_data = service.export_unvalidated

    send_data oscal_data,
              filename:    "#{@sap_document.name}_oscal_assessment-plan_unvalidated_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def update_metadata
    if @sap_document.update(document_metadata_params)
      flash[:success] = "Document updated"
    else
      flash[:error] = @sap_document.errors.full_messages.join(", ")
    end
    redirect_to sap_document_path(@sap_document)
  end

  def status
    render json: {
      status: @sap_document.status,
      error_message: @sap_document.error_message
    }
  end

  private

  def document_metadata_params
    permitted = params.require(:sap_document).permit(:name, :sap_version, :oscal_version, :description,
      :assessment_type, :assessment_start, :assessment_end)
    merge_metadata_extra(permitted, :sap_document)
  end

  def set_sap_document
    @sap_document = SapDocument.find(params[:id])
  end

  def create_from_wizard
    wizard_params = params.require(:sap_document).permit(
      :name, :ssp_document_id, :profile_document_id,
      :assessment_type, :assessment_start, :assessment_end, :description,
      control_ids: [], assessment_methods: {}
    )

    ssp = SspDocument.find_by(id: wizard_params[:ssp_document_id]) if wizard_params[:ssp_document_id].present?
    profile = ProfileDocument.find_by(id: wizard_params[:profile_document_id]) if wizard_params[:profile_document_id].present?

    name = wizard_params[:name].presence || "SAP - #{ssp&.name || 'Assessment Plan'} - #{Date.today}"

    begin
      sap = SapGeneratorService.new(
        name: name,
        ssp_document: ssp,
        profile_document: profile,
        assessment_type: wizard_params[:assessment_type].presence || "initial",
        assessment_start: wizard_params[:assessment_start],
        assessment_end: wizard_params[:assessment_end],
        description: wizard_params[:description],
        selected_control_ids: wizard_params[:control_ids]&.reject(&:blank?),
        assessment_methods: wizard_params[:assessment_methods]&.to_unsafe_h
      ).generate

      flash[:success] = "Security Assessment Plan created with #{sap.sap_controls.count} controls"
      redirect_to sap
    rescue StandardError => e
      flash[:error] = "Error creating assessment plan: #{e.message}"
      @sap_document = SapDocument.new
      @ssp_documents = SspDocument.where(status: "completed").order(:name)
      @profile_documents = ProfileDocument.where(status: "completed").order(:name)
      render :new
    end
  end

  def build_method_heatmap(scope)
    rows = scope.where.not(control_family: [ nil, "" ])
                .group(:control_family, :assessment_method).count

    data = {}
    rows.each do |(family, method), count|
      m = method.presence || "(None)"
      data[family] ||= {}
      data[family][m] = count
    end

    families = data.keys.sort
    all_methods = data.values.flat_map(&:keys).uniq
    ordered = METHOD_ORDER.select { |m| all_methods.include?(m) }
    ordered += (all_methods - METHOD_ORDER).sort

    [ data, families, ordered ]
  end
end
