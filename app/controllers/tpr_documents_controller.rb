class TprDocumentsController < ApplicationController
  include Pagy::Method

  CONTROLS_PER_PAGE = 50

  before_action :set_tpr_document, only: [
    :show, :update, :destroy, :download_json, :download_excel, :edit_control, :status
  ]

  helper_method :filter_params

  def index
    @tpr_documents = TprDocument.order(created_at: :desc)
  end

  def show
    # Short-circuit for documents still being processed
    return if @tpr_document.pending? || @tpr_document.processing? || @tpr_document.failed?

    controls_scope = @tpr_document.tpr_controls

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
        "cached_result = :status OR (cached_result IS NULL AND tpr_controls.id IN " \
        "(SELECT tpr_control_id FROM tpr_control_fields WHERE field_name = 'result' AND field_value = :status))",
        status: params[:status]
      )
    end

    # Paginate (explicit order since default_scope was removed for query performance)
    @pagy, @controls = pagy(
      :offset,
      filtered.order(:row_order).includes(:tpr_control_fields),
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
    control = @tpr_document.tpr_controls.find(params[:tpr_control_id])

    (params[:fields] || {}).each do |field_name, value|
      field = control.tpr_control_fields.find_or_initialize_by(field_name: field_name.to_s)
      field.field_value = value.to_s.strip
      field.save!
    end

    flash[:success] = "Test updated successfully"
    redirect_to tpr_document_path(@tpr_document, filter_params)
  rescue ActiveRecord::RecordNotFound
    flash[:error] = "Control not found"
    redirect_to @tpr_document
  rescue StandardError => e
    flash[:error] = "Error updating: #{e.message}"
    redirect_to @tpr_document
  end

  def new
    @tpr_document = TprDocument.new
  end

  def create
    uploaded_file = params[:tpr_document][:file]

    if uploaded_file.nil?
      flash[:error] = "Please select a file to upload"
      render :new and return
    end

    # Write to a persistent file (not Tempfile, which auto-deletes on GC
    # before Sidekiq can process it). The job cleans up via FileUtils.rm_f.
    persist_path = Rails.root.join("tmp", "tpr_#{SecureRandom.hex(8)}#{File.extname(uploaded_file.original_filename)}")
    File.open(persist_path, "wb") { |f| f.write(uploaded_file.read) }

    begin
      @tpr_document = TprDocument.create!(
        name:              File.basename(uploaded_file.original_filename, ".*"),
        file_type:         "excel",
        original_filename: uploaded_file.original_filename,
        status:            "pending"
      )
      @tpr_document.file.attach(uploaded_file)

      TprConversionJob.perform_later(@tpr_document.id, persist_path.to_s)

      flash[:success] = "Test Plan Results workbook uploaded. Processing in background..."
      redirect_to @tpr_document
    rescue StandardError => e
      FileUtils.rm_f(persist_path)
      flash[:error] = "Error uploading file: #{e.message}"
      render :new
    end
  end

  def download_json
    json_data = JsonExportService.export_tpr(@tpr_document)

    send_data json_data,
              filename:    "#{@tpr_document.name}_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_excel
    excel_data = TprExcelExportService.new(@tpr_document).export

    send_data excel_data,
              filename:    "#{@tpr_document.name}_#{Date.today}.xlsx",
              type:        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
              disposition: "attachment"
  end

  def edit_control
    @control = @tpr_document.tpr_controls
                             .includes(:tpr_control_fields)
                             .find(params[:tpr_control_id])
    @catalog_guidance = {}
    normalized = normalize_ctrl_id(@control.control_id)
    if normalized
      ctrl = CatalogControl.find_by(control_id: normalized)
      @catalog_guidance[normalized] = ctrl if ctrl
    end

    render partial: "tpr_documents/edit_control_form",
           locals: { control: @control, tpr_document: @tpr_document }
  end

  def status
    render json: {
      status: @tpr_document.status,
      error_message: @tpr_document.error_message
    }
  end

  def destroy
    @tpr_document.destroy
    flash[:success] = "Test Plan Results document deleted"
    redirect_to tpr_documents_path
  end

  private

  def set_tpr_document
    @tpr_document = TprDocument.find(params[:id])
  end

  def filter_params
    params.permit(:section, :family, :status, :asset, :environment, :page).to_h
  end

  TPR_STATUS_ORDER = [
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
      # join to tpr_control_fields for result, compute family from control_id
      rows = {}
      scope.includes(:tpr_control_fields).find_each(batch_size: 1000) do |control|
        family = control.control_id.to_s.split("-").first.upcase
        next if family.blank?
        result_field = control.tpr_control_fields.find { |f| f.field_name == "result" }
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
    ordered      = TPR_STATUS_ORDER.select { |s| all_statuses.include?(s) }
    ordered     += (all_statuses - TPR_STATUS_ORDER).sort

    [ data, families, ordered ]
  end
end
