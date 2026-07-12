class PoamDocumentsController < ApplicationController
  include FileUploadable
  include Publishable
  include OscalExportable

  before_action :set_poam_document, only: %i[
    show destroy download_json download_oscal
    download_oscal_validated download_oscal_unvalidated
    download_yaml download_xml validate_oscal_export
    update_metadata status update publish publish_check
  ]
  before_action :ensure_editable!, only: [ :update, :update_metadata, :publish ]

  RISK_STATUS_ORDER = %w[open investigating remediating deviation-requested deviation-approved closed].freeze
  IMPACT_ORDER      = %w[high medium low].freeze

  def index
    @poam_documents = PoamDocument.order(created_at: :desc)
    @total_count = @poam_documents.count
    @items_count = PoamItem.count
    @completed_count = @poam_documents.where(status: "completed").count
    @poam_documents = @poam_documents.search_text(params[:q]) # #672 — filter listed rows; tiles keep totals
  end

  def show
    return if @poam_document.pending? || @poam_document.processing? || @poam_document.failed?

    items_scope = @poam_document.poam_items

    @total_items       = items_scope.count
    @risk_count        = @poam_document.poam_risks.count
    @observation_count = @poam_document.poam_observations.count
    @finding_count     = @poam_document.poam_findings.count
    @component_count   = @poam_document.poam_local_components.count

    @status_counts = items_scope.where.not(risk_status: [ nil, "" ]).group(:risk_status).count
    @impact_counts = items_scope.where.not(impact: [ nil, "" ]).group(:impact).count

    @heatmap_data, @heatmap_statuses, @heatmap_impacts = build_heatmap(items_scope)

    filtered = items_scope
    filtered = filtered.where(risk_status: params[:risk_status]) if params[:risk_status].present?
    filtered = filtered.where(impact: params[:impact])           if params[:impact].present?

    @filtered_count = filtered.count
    @items = filtered.order(:row_order).includes(
      :poam_item_risks, { poam_risks: { poam_remediations: :poam_milestones } },
      :poam_item_observations, :poam_observations,
      :poam_item_findings, :poam_findings
    )
  end

  def new
    @poam_document = PoamDocument.new
    load_ssp_options_grouped
  end

  def create
    # Wizard create (no file) vs file upload
    if params.dig(:poam_document, :file).blank? && params.dig(:poam_document, :files).blank?
      attrs = wizard_params.to_h
      attrs[:poam_version]  = attrs[:poam_version].presence  || "1.0.0"
      attrs[:oscal_version] = attrs[:oscal_version].presence || "1.1.2"
      @poam_document = PoamDocument.new(attrs)
      @poam_document.status = "completed"

      if @poam_document.save
        audit_log("poam_document_created", subject: @poam_document,
                  metadata: { name: @poam_document.name, method: "wizard" })
        flash[:success] = "POA&M '#{@poam_document.name}' created. Add items to get started."
        redirect_to poam_document_path(@poam_document)
      else
        flash.now[:error] = @poam_document.errors.full_messages.join(", ")
        load_ssp_options_grouped
        render :new, status: :unprocessable_entity
      end
    else
      handle_multi_file_upload(:poam, param_key: :poam_document)
    end
  end

  def update
    item = @poam_document.poam_items.find(params[:poam_item_id])

    editable_fields = %w[risk_status internal_notes closure_evidence]
    update_attrs = {}

    (params[:fields] || {}).each do |field_name, value|
      fname = field_name.to_s
      unless editable_fields.include?(fname)
        raise StandardError, "Field '#{fname}' is not editable"
      end
      update_attrs[fname] = value.to_s.strip
    end

    item.update!(update_attrs) if update_attrs.any?

    # Sync risk_status to primary risk record
    if update_attrs["risk_status"].present?
      primary_risk = item.primary_risk
      primary_risk&.update!(status: update_attrs["risk_status"])
    end

    @poam_document.regenerate_oscal_uuid!
    flash[:success] = "POA&M item updated"
    redirect_to poam_document_path(@poam_document, filter_params)
  rescue StandardError => e
    flash[:error] = "Error updating: #{e.message}"
    redirect_to @poam_document
  end

  def destroy
    name = @poam_document.name
    if @poam_document.destroy
      audit_log("poam_document_deleted", subject: @poam_document, metadata: { name: name })
      flash[:success] = "POA&M '#{name}' deleted."
      redirect_to poam_documents_path
    else
      audit_log("poam_document_delete_blocked", subject: @poam_document,
        metadata: { name: name, reason: @poam_document.errors.full_messages.join(", ") })
      flash[:error] = @poam_document.errors.full_messages.join(", ")
      redirect_to poam_document_path(@poam_document)
    end
  end

  def download_json
    json_data = JsonExportService.export_poam(@poam_document)

    audit_log("poam_document_exported", subject: @poam_document, metadata: { name: @poam_document.name, format: "json" })
    send_data json_data,
              filename:    "#{@poam_document.name}_#{Date.today}.json",
              type:        JSON_CONTENT_TYPE,
              disposition: "attachment"
  end

  def download_oscal
    service = OscalPoamExportService.new(@poam_document)
    result = service.validation_result

    if result.valid?
      audit_log("poam_document_exported", subject: @poam_document, metadata: { name: @poam_document.name, format: "oscal" })
      send_data service.export,
                filename:    "#{@poam_document.name}_oscal_poam_#{Date.today}.json",
                type:        JSON_CONTENT_TYPE,
                disposition: "attachment"
    else
      Rails.logger.warn("OSCAL validation failed for POA&M #{@poam_document.id}: #{result.errors.first(3).join('; ')}")
      flash[:warning] = SCHEMA_VALIDATION_FAILED_FLASH
      redirect_to poam_document_path(@poam_document, oscal_validation_failed: 1, oscal_format: "json")
    end
  end

  def download_oscal_validated
    service = OscalPoamExportService.new(@poam_document)
    oscal_data = service.export

    audit_log("poam_document_exported", subject: @poam_document, metadata: { name: @poam_document.name, format: "oscal_validated" })
    send_data oscal_data,
              filename:    "#{@poam_document.name}_oscal_poam_#{Date.today}.json",
              type:        JSON_CONTENT_TYPE,
              disposition: "attachment"
  end

  def download_oscal_unvalidated
    service = OscalPoamExportService.new(@poam_document)
    oscal_data = service.export_unvalidated

    audit_log("poam_document_exported", subject: @poam_document, metadata: { name: @poam_document.name, format: "oscal_unvalidated" })
    send_data oscal_data,
              filename:    "#{@poam_document.name}_oscal_poam_unvalidated_#{Date.today}.json",
              type:        JSON_CONTENT_TYPE,
              disposition: "attachment"
  end

  def download_yaml
    service = OscalPoamExportService.new(@poam_document)
    json_string = params[:skip_validation] ? service.export_unvalidated : service.export
    yaml_data = OscalExportFormatService.to_yaml(json_string)

    audit_log("poam_document_exported", subject: @poam_document, metadata: { name: @poam_document.name, format: "yaml" })
    send_data yaml_data,
              filename:    "#{@poam_document.name}_oscal_poam_#{Date.today}.yaml",
              type:        "application/x-yaml",
              disposition: "attachment"
  rescue OscalValidationError => e
    Rails.logger.warn("OSCAL YAML validation failed for POA&M #{@poam_document.id}: #{e.message.to_s.truncate(300)}")
    flash[:warning] = SCHEMA_VALIDATION_FAILED_FLASH
    redirect_to poam_document_path(@poam_document, oscal_validation_failed: 1, oscal_format: "yaml")
  end

  def download_xml
    service = OscalPoamExportService.new(@poam_document)
    json_string = params[:skip_validation] ? service.export_unvalidated : service.export
    xml_data = OscalExportFormatService.to_xml(json_string, :poam)

    audit_log("poam_document_exported", subject: @poam_document, metadata: { name: @poam_document.name, format: "xml" })
    send_data xml_data,
              filename:    "#{@poam_document.name}_oscal_poam_#{Date.today}.xml",
              type:        "application/xml",
              disposition: "attachment"
  rescue OscalValidationError => e
    Rails.logger.warn("OSCAL XML validation failed for POA&M #{@poam_document.id}: #{e.message.to_s.truncate(300)}")
    flash[:warning] = SCHEMA_VALIDATION_FAILED_FLASH
    redirect_to poam_document_path(@poam_document, oscal_validation_failed: 1, oscal_format: "xml")
  end

  def update_metadata
    if @poam_document.update(document_metadata_params)
      @poam_document.regenerate_oscal_uuid!
      audit_log("poam_document_updated", subject: @poam_document, metadata: { name: @poam_document.name, metadata_update: true })
      flash[:success] = "Document updated"
    else
      flash[:error] = @poam_document.errors.full_messages.join(", ")
    end
    redirect_to poam_document_path(@poam_document)
  end

  def status
    render json: {
      status: @poam_document.status,
      error_message: @poam_document.error_message
    }
  end

  private

  def publish_config
    { document: @poam_document, audit_event: "poam_document_published",
      redirect_path: poam_document_path(@poam_document), label: "POA&M" }
  end

  def set_poam_document
    @poam_document = PoamDocument.find_by!(slug: params[:id])
  end

  def wizard_params
    params.require(:poam_document).permit(:name, :description, :system_id,
                                          :authorization_boundary_id,
                                          :poam_version, :oscal_version,
                                          :ssp_document_id)
  end

  # Load SSPs grouped by authorization boundary for the wizard's "Source SSP"
  # dropdown (#389). Each group is the boundary's name; options are SSPs
  # belonging to that boundary, plus a top-level "(unscoped)" group for SSPs
  # without a boundary association. Rendered as <optgroup> in the form.
  def load_ssp_options_grouped
    ssps = SspDocument.where(deleted_at: nil)
                      .order(:authorization_boundary_id, :name)
                      .includes(:authorization_boundary)

    @ssp_options_by_boundary = ssps.group_by do |s|
      s.authorization_boundary&.name || "(unscoped)"
    end
  end

  # OscalExportable hooks
  def oscal_export_document = @poam_document
  def oscal_export_service(doc) = OscalPoamExportService.new(doc)
  def oscal_document_type_label = "POA&M"

  def ensure_editable!
    return unless @poam_document.published_lifecycle?

    flash[:error] = "This POA&M is published and read-only. Create a copy to make changes."
    redirect_to poam_document_path(@poam_document)
  end

  def document_metadata_params
    permitted = params.require(:poam_document).permit(:name, :poam_version, :oscal_version, :description)
    merge_metadata_extra(permitted, :poam_document)
  end

  def filter_params
    params.except(:controller, :action, :id).permit(:risk_status, :impact).to_h
  end

  def build_heatmap(scope)
    rows = scope.where.not(risk_status: [ nil, "" ])
                .where.not(impact: [ nil, "" ])
                .group(:risk_status, :impact).count

    data = {}
    rows.each do |(status, impact), count|
      data[status] ||= {}
      data[status][impact] = count
    end

    statuses = RISK_STATUS_ORDER.select { |s| data.key?(s) } +
               (data.keys - RISK_STATUS_ORDER).sort
    all_impacts = data.values.flat_map(&:keys).uniq
    impacts = IMPACT_ORDER.select { |i| all_impacts.include?(i) } +
              (all_impacts - IMPACT_ORDER).sort

    [ data, statuses, impacts ]
  end
end
