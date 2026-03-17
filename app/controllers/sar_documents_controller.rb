class SarDocumentsController < ApplicationController
  include FileUploadable
  include Pagy::Method
  include Publishable

  CONTROLS_PER_PAGE = 50

  before_action :set_sar_document, only: [
    :show, :update, :destroy, :download_json, :download_excel,
    :download_oscal, :download_oscal_validated, :download_oscal_unvalidated,
    :download_yaml, :download_xml,
    :edit_control, :status, :update_metadata, :enrich, :update_enrich,
    :publish, :publish_check
  ]
  before_action :ensure_editable!, only: [ :update, :update_metadata, :publish ]

  helper_method :filter_params

  def index
    @sar_documents = SarDocument.order(created_at: :desc)
    @total_count = @sar_documents.count
    @controls_count = SarControl.count
    @completed_count = @sar_documents.where(status: "completed").count
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

    @sar_document.regenerate_oscal_uuid!
    audit_log("sar_document_updated", subject: @sar_document, metadata: { name: @sar_document.name, control_id: params[:sar_control_id] })

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

  def wizard
    @sar_document = SarDocument.new
    @sap_documents = SapDocument.where(status: "completed").order(:name)
  end

  def create_from_wizard
    service = SarWizardService.new(wizard_params)
    document = service.create

    audit_log("sar_document_created", subject: document, metadata: { name: document.name, creation_method: "wizard" })

    flash[:success] = "SAR '#{document.name}' created from wizard."
    redirect_to sar_document_path(document)
  rescue StandardError => e
    flash[:error] = "Error creating SAR: #{e.message}"
    redirect_to wizard_sar_documents_path
  end

  def download_json
    json_data = JsonExportService.export_sar(@sar_document)

    audit_log("sar_document_exported", subject: @sar_document, metadata: { name: @sar_document.name, format: "json" })

    send_data json_data,
              filename:    "#{@sar_document.name}_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_excel
    excel_data = SarExcelExportService.new(@sar_document).export

    audit_log("sar_document_exported", subject: @sar_document, metadata: { name: @sar_document.name, format: "excel" })

    send_data excel_data,
              filename:    "#{@sar_document.name}_#{Date.today}.xlsx",
              type:        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
              disposition: "attachment"
  end

  def download_oscal
    service = OscalSarExportService.new(@sar_document)
    result = service.validation_result

    if result.valid?
      audit_log("sar_document_exported", subject: @sar_document, metadata: { name: @sar_document.name, format: "oscal" })

      send_data service.export,
                filename:    "#{@sar_document.name}_oscal_sar_#{Date.today}.json",
                type:        "application/json",
                disposition: "attachment"
    else
      Rails.logger.warn("OSCAL validation failed for SAR #{@sar_document.id}: #{result.errors.first(3).join('; ')}")
      flash[:warning] = "OSCAL export failed schema validation. Use the unvalidated download instead."
      redirect_to sar_document_path(@sar_document)
    end
  end

  def download_oscal_validated
    service = OscalSarExportService.new(@sar_document)
    oscal_data = service.export

    audit_log("sar_document_exported", subject: @sar_document, metadata: { name: @sar_document.name, format: "oscal_validated" })

    send_data oscal_data,
              filename:    "#{@sar_document.name}_oscal_ar_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_oscal_unvalidated
    service = OscalSarExportService.new(@sar_document)
    oscal_data = service.export_unvalidated

    audit_log("sar_document_exported", subject: @sar_document, metadata: { name: @sar_document.name, format: "oscal_unvalidated" })

    send_data oscal_data,
              filename:    "#{@sar_document.name}_oscal_ar_unvalidated_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_yaml
    json_string = OscalSarExportService.new(@sar_document).export
    yaml_data = OscalExportFormatService.to_yaml(json_string)

    audit_log("sar_document_exported", subject: @sar_document, metadata: { name: @sar_document.name, format: "yaml" })

    send_data yaml_data,
              filename:    "#{@sar_document.name}_oscal_sar_#{Date.today}.yaml",
              type:        "application/x-yaml",
              disposition: "attachment"
  end

  def download_xml
    json_string = OscalSarExportService.new(@sar_document).export
    xml_data = OscalExportFormatService.to_xml(json_string, :assessment_results)

    audit_log("sar_document_exported", subject: @sar_document, metadata: { name: @sar_document.name, format: "xml" })

    send_data xml_data,
              filename:    "#{@sar_document.name}_oscal_sar_#{Date.today}.xml",
              type:        "application/xml",
              disposition: "attachment"
  end

  def enrich
    @results      = @sar_document.sar_results.order(:position)
    @observations = @sar_document.sar_results.flat_map { |r| r.sar_observations.to_a }
    @findings     = @sar_document.sar_results.flat_map { |r| r.sar_findings.to_a }
    @risks        = @sar_document.sar_results.flat_map { |r| r.sar_risks.to_a }
  end

  def update_enrich
    ActiveRecord::Base.transaction do
      @sar_document.update!(enrich_params)
      sync_results
      sync_observations
      sync_findings
      sync_risks
      auto_generate_from_excel if params.dig(:sar_document, :auto_generate) == "1"
    end

    @sar_document.regenerate_oscal_uuid!
    audit_log("sar_document_updated", subject: @sar_document, metadata: { name: @sar_document.name, enrichment: true })

    flash[:success] = "SAR enrichment data saved."
    redirect_to sar_document_path(@sar_document)
  rescue StandardError => e
    flash[:error] = "Error saving enrichment: #{e.message}"
    redirect_to enrich_sar_document_path(@sar_document)
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

  def update_metadata
    if @sar_document.update(document_metadata_params)
      @sar_document.regenerate_oscal_uuid!
      audit_log("sar_document_updated", subject: @sar_document, metadata: { name: @sar_document.name, metadata_update: true })
      flash[:success] = "Document updated"
    else
      flash[:error] = @sar_document.errors.full_messages.join(", ")
    end
    redirect_to sar_document_path(@sar_document)
  end

  def status
    render json: {
      status: @sar_document.status,
      error_message: @sar_document.error_message
    }
  end

  def destroy
    name = @sar_document.name
    if @sar_document.destroy
      audit_log("sar_document_deleted", subject: @sar_document, metadata: { name: name })
      flash[:success] = "SAR '#{name}' deleted."
      redirect_to sar_documents_path
    else
      audit_log("sar_document_delete_blocked", subject: @sar_document,
        metadata: { name: name, reason: @sar_document.errors.full_messages.join(", ") })
      flash[:error] = @sar_document.errors.full_messages.join(", ")
      redirect_to sar_document_path(@sar_document)
    end
  end

  private

  def document_metadata_params
    permitted = params.require(:sar_document).permit(:name, :sar_version, :oscal_version, :description)
    merge_metadata_extra(permitted, :sar_document)
  end

  def wizard_params
    params.permit(
      :name, :description, :sap_document_id,
      :assessment_start, :assessment_end
    )
  end

  def enrich_params
    params.require(:sar_document).permit(
      :description, :import_ap_href, :oscal_version,
      :assessment_start, :assessment_end
    )
  end

  # ── Enrichment sync helpers ──────────────────────────────────────

  def sync_results
    incoming = params.dig(:sar_document, :results) || []
    existing_ids = @sar_document.sar_results.pluck(:id)
    seen_ids = []

    incoming.each_with_index do |r_params, idx|
      r_params = r_params.permit(:id, :title, :description, :start_time, :end_time)
      if r_params[:id].present? && existing_ids.include?(r_params[:id].to_i)
        record = @sar_document.sar_results.find(r_params[:id])
        record.update!(r_params.except(:id).merge(position: idx))
        seen_ids << record.id
      else
        next if r_params[:start_time].blank?
        record = @sar_document.sar_results.create!(
          uuid: SecureRandom.uuid,
          title: r_params[:title].presence || "Assessment Result",
          description: r_params[:description],
          start_time: r_params[:start_time],
          end_time: r_params[:end_time],
          position: idx
        )
        seen_ids << record.id
      end
    end

    @sar_document.sar_results.where.not(id: seen_ids).destroy_all if incoming.any?
  end

  def sync_observations
    incoming = params.dig(:sar_document, :observations) || []
    return if incoming.empty?

    default_result = @sar_document.sar_results.first
    return unless default_result

    existing_ids = default_result.sar_observations.pluck(:id)
    seen_ids = []

    incoming.each do |o_params|
      o_params = o_params.permit(:id, :sar_result_id, :title, :description, :collected)
      result = if o_params[:sar_result_id].present?
        @sar_document.sar_results.find_by(id: o_params[:sar_result_id]) || default_result
      else
        default_result
      end

      if o_params[:id].present? && existing_ids.include?(o_params[:id].to_i)
        record = SarObservation.find(o_params[:id])
        record.update!(o_params.except(:id, :sar_result_id))
        seen_ids << record.id
      else
        record = result.sar_observations.create!(
          uuid: SecureRandom.uuid,
          title: o_params[:title].presence || "Observation",
          description: o_params[:description].presence || "No description provided.",
          collected: o_params[:collected].present? ? o_params[:collected] : Time.current
        )
        seen_ids << record.id
      end
    end
  end

  def sync_findings
    incoming = params.dig(:sar_document, :findings) || []
    return if incoming.empty?

    default_result = @sar_document.sar_results.first
    return unless default_result

    incoming.each do |f_params|
      f_params = f_params.permit(:id, :sar_result_id, :title, :description, :target_control_id, :target_status)
      result = if f_params[:sar_result_id].present?
        @sar_document.sar_results.find_by(id: f_params[:sar_result_id]) || default_result
      else
        default_result
      end

      target_data = {
        "type" => "objective-id",
        "target-id" => f_params[:target_control_id].presence || "unknown",
        "status" => { "state" => f_params[:target_status].presence || "not-satisfied" }
      }

      if f_params[:id].present?
        record = SarFinding.find_by(id: f_params[:id])
        record&.update!(
          title: f_params[:title],
          description: f_params[:description],
          target_data: target_data
        )
      else
        result.sar_findings.create!(
          uuid: SecureRandom.uuid,
          title: f_params[:title].presence || "Finding",
          description: f_params[:description].presence || "No description provided.",
          target_data: target_data
        )
      end
    end
  end

  def sync_risks
    incoming = params.dig(:sar_document, :risks) || []
    return if incoming.empty?

    default_result = @sar_document.sar_results.first
    return unless default_result

    incoming.each do |r_params|
      r_params = r_params.permit(:id, :sar_result_id, :title, :description, :status)
      result = if r_params[:sar_result_id].present?
        @sar_document.sar_results.find_by(id: r_params[:sar_result_id]) || default_result
      else
        default_result
      end

      if r_params[:id].present?
        record = SarRisk.find_by(id: r_params[:id])
        record&.update!(r_params.except(:id, :sar_result_id))
      else
        result.sar_risks.create!(
          uuid: SecureRandom.uuid,
          title: r_params[:title].presence || "Risk",
          description: r_params[:description].presence || "No description provided.",
          status: r_params[:status].presence || "open"
        )
      end
    end
  end

  def auto_generate_from_excel
    return if @sar_document.sar_results.exists?

    result = @sar_document.sar_results.create!(
      uuid: SecureRandom.uuid,
      title: "Assessment Results for #{@sar_document.name}",
      description: "Auto-generated from Excel assessment data.",
      start_time: @sar_document.assessment_start || @sar_document.created_at || Time.current,
      end_time: @sar_document.assessment_end || Time.current,
      position: 0
    )

    @sar_document.sar_controls.includes(:sar_control_fields).find_each do |control|
      next if control.control_id.blank?

      field_map = control.sar_control_fields.index_by(&:field_name)
      result_val = field_map["result"]&.field_value.presence || "Not Tested"

      # Create observation
      obs = result.sar_observations.create!(
        uuid: SecureRandom.uuid,
        title: "Assessment of #{control.control_id}",
        description: "Control: #{control.control_id}\nResult: #{result_val}",
        collected: @sar_document.assessment_start || @sar_document.created_at || Time.current,
        methods_data: [ "TEST" ]
      )

      # Create finding
      control_id = control.control_id.strip.downcase.gsub(/\s+/, "-").gsub("(", ".").gsub(")", "")
      status_state = result_val.to_s.downcase.start_with?("pass") ? "satisfied" : "not-satisfied"

      finding = result.sar_findings.create!(
        uuid: SecureRandom.uuid,
        title: "Finding for #{control.control_id}",
        description: "Assessment finding for control #{control.control_id}: #{result_val}",
        target_data: {
          "type" => "objective-id",
          "target-id" => control_id,
          "status" => { "state" => status_state }
        }
      )

      # Link finding to observation
      SarFindingObservation.create!(sar_finding: finding, sar_observation: obs)
    end
  end

  def set_sar_document
    @sar_document = SarDocument.find_by!(slug: params[:id])
  end

  def publish_config
    {
      document: @sar_document,
      audit_event: "sar_document_published",
      redirect_path: sar_document_path(@sar_document),
      label: "SAR"
    }
  end

  def ensure_editable!
    return unless @sar_document.published_lifecycle?

    flash[:error] = "This SAR is published and read-only. Create a copy to make changes."
    redirect_to sar_document_path(@sar_document)
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
