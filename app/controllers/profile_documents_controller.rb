class ProfileDocumentsController < ApplicationController
  include FileUploadable
  skip_before_action :require_authentication, only: [ :index, :show ]

  before_action :set_profile_document, only: %i[
    show destroy download_json download_oscal
    download_oscal_validated download_oscal_unvalidated status
    update_metadata copy
  ]

  PRIORITY_ORDER = %w[P1 P2 P3].freeze

  def index
    @profile_documents = ProfileDocument.order(created_at: :desc)
    @total_count = @profile_documents.count
    @controls_count = ProfileControl.count
    @completed_count = @profile_documents.where(status: "completed").count
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
    name = @profile_document.name
    audit_log("profile_document_deleted", subject: @profile_document, metadata: { name: name })
    @profile_document.destroy
    flash[:success] = "Profile (Baseline) deleted"
    redirect_to profile_documents_path
  end

  def download_json
    json_data = JsonExportService.export_profile(@profile_document)

    audit_log("profile_document_exported", subject: @profile_document, metadata: { name: @profile_document.name, format: "json" })
    send_data json_data,
              filename:    "#{@profile_document.name}_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_oscal
    service = OscalProfileExportService.new(@profile_document)
    result = service.validation_result

    if result.valid?
      audit_log("profile_document_exported", subject: @profile_document, metadata: { name: @profile_document.name, format: "oscal" })
      send_data service.export,
                filename:    "#{@profile_document.name}_oscal_profile_#{Date.today}.json",
                type:        "application/json",
                disposition: "attachment"
    else
      Rails.logger.warn("OSCAL validation failed for Profile #{@profile_document.id}: #{result.errors.first(3).join('; ')}")
      flash[:warning] = "OSCAL export failed schema validation. Use the unvalidated download instead."
      redirect_to profile_document_path(@profile_document)
    end
  end

  def download_oscal_validated
    service = OscalProfileExportService.new(@profile_document)
    oscal_data = service.export

    audit_log("profile_document_exported", subject: @profile_document, metadata: { name: @profile_document.name, format: "oscal_validated" })
    send_data oscal_data,
              filename:    "#{@profile_document.name}_oscal_profile_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_oscal_unvalidated
    service = OscalProfileExportService.new(@profile_document)
    oscal_data = service.export_unvalidated

    audit_log("profile_document_exported", subject: @profile_document, metadata: { name: @profile_document.name, format: "oscal_unvalidated" })
    send_data oscal_data,
              filename:    "#{@profile_document.name}_oscal_profile_unvalidated_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def update_metadata
    if @profile_document.update(document_metadata_params)
      audit_log("profile_document_updated", subject: @profile_document, metadata: { name: @profile_document.name, metadata_update: true })
      flash[:success] = "Document updated"
    else
      flash[:error] = @profile_document.errors.full_messages.join(", ")
    end
    redirect_to profile_document_path(@profile_document)
  end

  def copy
    service = DocumentDuplicationService.new(@profile_document)
    copy = service.duplicate

    audit_log("profile_document_copied", subject: copy, metadata: { source_id: @profile_document.id, source_name: @profile_document.name, copy_name: copy.name })
    flash[:success] = "Profile duplicated as '#{copy.name}'"
    redirect_to profile_document_path(copy)
  end

  def select_catalog
    @catalogs = ControlCatalog.order(:name)
  end

  def create_from_catalog
    catalog = ControlCatalog.find(params[:catalog_id])
    control_ids = Array(params[:control_ids]).reject(&:blank?)

    if control_ids.empty?
      flash[:error] = "Please select at least one control"
      redirect_to select_catalog_profile_documents_path and return
    end

    profile = ProfileDocument.create!(
      name: params[:profile_name].presence || "Profile from #{catalog.name}",
      baseline_level: params[:baseline_level],
      control_catalog: catalog,
      status: "completed",
      description: "Created from #{catalog.name} catalog"
    )

    catalog_controls = catalog.catalog_controls.where(control_id: control_ids).includes(:control_family)
    catalog_controls.each_with_index do |cc, idx|
      profile.profile_controls.create!(
        control_id: cc.control_id,
        title: cc.title,
        control_family: cc.control_family&.code || cc.family_code,
        row_order: idx
      )
    end

    audit_log("profile_document_created", subject: profile, metadata: { name: profile.name, creation_method: "catalog" })
    flash[:success] = "Profile created with #{profile.profile_controls.count} controls from #{catalog.name}"
    redirect_to profile_document_path(profile)
  end

  def status
    render json: {
      status: @profile_document.status,
      error_message: @profile_document.error_message
    }
  end

  private

  def document_metadata_params
    permitted = params.require(:profile_document).permit(:name, :profile_version, :oscal_version, :description, :published)
    merge_metadata_extra(permitted, :profile_document)
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
