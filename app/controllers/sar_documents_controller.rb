class SarDocumentsController < ApplicationController
  include FileUploadable
  include Pagy::Method

  CONTROLS_PER_PAGE = 50

  before_action :set_sar_document, only: [
    :show, :update, :destroy, :download_json, :download_excel, :edit_control, :status
  ]

  helper_method :filter_params

  def index
    @sar_documents = SarDocument.order(created_at: :desc)
  end

  def show
    # Short-circuit for documents still being processed
    return if @sar_document.pending? || @sar_document.processing? || @sar_document.failed?

    controls_scope = @sar_document.sar_controls

    # Filter options — TRIM + DISTINCT to deduplicate values with whitespace differences
    @sections     = controls_scope.where.not(section: nil)
                                  .distinct.order(:section).pluck(:section)
    @assets       = controls_scope.where.not(subject_asset: [ nil, "" ])
                                  .pluck(Arel.sql("DISTINCT TRIM(subject_asset)")).sort
    @environments = controls_scope.where.not(subject_environment: [ nil, "" ])
                                  .pluck(Arel.sql("DISTINCT TRIM(subject_environment)")).sort

    # Apply context filters (section/asset/env) BEFORE building heatmap so
    # the family cards reflect the active context selection
    base_filtered = controls_scope
    base_filtered = base_filtered.where(section: params[:section])                 if params[:section].present?
    base_filtered = base_filtered.where(subject_asset: params[:asset])             if params[:asset].present?
    base_filtered = base_filtered.where(subject_environment: params[:environment]) if params[:environment].present?

    # Heatmap built from context-filtered scope (responds to asset/env/section)
    @heatmap_data, @heatmap_families, @heatmap_statuses =
      build_heatmap_from_scope(base_filtered)

    # Apply family/status filters using raw SQL to avoid
    # #or structural incompatibility with :joins
    filtered = base_filtered

    if params[:family].present?
      filtered = filtered.where(
        "control_family = :family OR (control_family IS NULL AND UPPER(SPLIT_PART(control_id, '-', 1)) = :family)",
        family: params[:family]
      )
    end

    if params[:status].present?
      filtered = filtered.where(
        "cached_result = :status OR (cached_result IS NULL AND sar_controls.id IN " \
        "(SELECT sar_control_id FROM sar_control_fields WHERE field_name = 'result' AND field_value = :status))",
        status: params[:status]
      )
    end

    # Paginate (explicit order since default_scope was removed for query performance)
    @pagy, @controls = pagy(
      :offset,
      filtered.order(:row_order).includes(:sar_control_fields),
      limit: CONTROLS_PER_PAGE
    )

    # Catalog guidance lookup (only for the current page)
    normalized_ids = @controls.map { normalize_ctrl_id(_1.control_id) }.compact.uniq
    @catalog_guidance = CatalogControl.where(control_id: normalized_ids).index_by(&:control_id)

    # Totals for display
    @total_controls = controls_scope.count
    @filtered_count = filtered.count
  end

  def update
    control = @sar_document.sar_controls.find(params[:sar_control_id])

    (params[:fields] || {}).each do |field_name, value|
      field = control.sar_control_fields.find_or_initialize_by(field_name: field_name.to_s)
      field.field_value = value.to_s.strip
      field.save!
    end

    flash[:success] = "Assessment result updated successfully"
    redirect_to sar_document_path(@sar_document, filter_params)
  rescue ActiveRecord::RecordNotFound
    flash[:error] = "Control not found"
    redirect_to @sar_document
  rescue StandardError => e
    flash[:error] = "Error updating: #{e.message}"
    redirect_to @sar_document
  end

  def new
    @sar_document = SarDocument.new
  end

  def create
    handle_file_upload(:sar, param_key: :sar_document)
  end

  def download_json
    json_data = JsonExportService.export_sar(@sar_document)

    send_data json_data,
              filename:    "#{@sar_document.name}_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_excel
    excel_data = SarExcelExportService.new(@sar_document).export

    send_data excel_data,
              filename:    "#{@sar_document.name}_#{Date.today}.xlsx",
              type:        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
              disposition: "attachment"
  end

  def edit_control
    @control = @sar_document.sar_controls
                             .includes(:sar_control_fields)
                             .find(params[:sar_control_id])
    @catalog_guidance = {}
    normalized = normalize_ctrl_id(@control.control_id)
    if normalized
      ctrl = CatalogControl.find_by(control_id: normalized)
      @catalog_guidance[normalized] = ctrl if ctrl
    end

    render partial: "sar_documents/edit_control_form",
           locals: { control: @control, sar_document: @sar_document }
  end

  def status
    render json: {
      status: @sar_document.status,
      error_message: @sar_document.error_message
    }
  end

  def destroy
    @sar_document.destroy
    flash[:success] = "Security Assessment Results document deleted"
    redirect_to sar_documents_path
  end

  private

  def set_sar_document
    @sar_document = SarDocument.find(params[:id])
  end

  def filter_params
    params.except(:controller, :action, :id).permit(:section, :family, :status, :asset, :environment, :page).to_h
  end

  SAR_STATUS_ORDER = [
    "Pass", "Failed",
    "Final Satisfied", "Final - Not Satisfied", "Not Satisfied", "Not Specified",
    # Legacy
    "Partial", "Fail", "Not Tested", "Not Applicable"
  ].freeze

  def build_heatmap_from_scope(scope)
    scope = scope.where.not(control_id: [ nil, "" ])

    # Use denormalized columns if available, otherwise fall back to SQL extraction
    has_denormalized = scope.where.not(control_family: nil).exists?

    if has_denormalized
      rows = scope.group(:control_family, :cached_result).count
    else
      # Fallback for pre-existing data without denormalized columns:
      # join to sar_control_fields for result, compute family from control_id
      rows = {}
      scope.includes(:sar_control_fields).find_each(batch_size: 1000) do |control|
        family = control.control_id.to_s.split("-").first.upcase
        next if family.blank?
        result_field = control.sar_control_fields.find { |f| f.field_name == "result" }
        status = result_field&.field_value.presence || "(Unknown)"
        rows[[ family, status ]] ||= 0
        rows[[ family, status ]] += 1
      end
    end

    data = {}
    rows.each do |(family, result), count|
      status = result.presence || "(Unknown)"
      data[family] ||= {}
      data[family][status] = count
    end

    families     = data.keys.sort
    all_statuses = data.values.flat_map(&:keys).uniq
    ordered      = SAR_STATUS_ORDER.select { |s| all_statuses.include?(s) }
    ordered     += (all_statuses - SAR_STATUS_ORDER).sort

    [ data, families, ordered ]
  end
end
