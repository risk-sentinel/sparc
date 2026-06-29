class CdefDocumentsController < ApplicationController
  include FileUploadable
  include Publishable
  include OscalExportable
  include BulkDestroyable
  include DocumentApprovalActions
  skip_before_action :require_authentication, only: [ :index, :show ]
  # #629 — bulk delete is admin-only.
  before_action :authorize_admin!, only: [ :bulk_destroy ]

  before_action :set_cdef_document, only: %i[show destroy download_json download_oscal download_oscal_validated download_oscal_unvalidated download_yaml download_xml validate_oscal_export status update_metadata update_field copy publish publish_check create_control_resource link_control_resource unlink_control_resource update_statement bulk_apply bulk_apply_preview bulk_apply_confirm attach_profile populate_from_profile submit_for_review approve reject]
  before_action :ensure_editable!, only: [ :update_metadata, :update_field, :publish, :create_control_resource, :link_control_resource, :unlink_control_resource, :update_statement, :attach_profile, :populate_from_profile, :submit_for_review ]
  # Issue #488 — same RBAC bucket as the DISA CCI "Refresh Now" button on
  # ConvertersController. Treats AWS Labs catalog refresh as an
  # authoritative-upstream-content operation alongside DISA CCI / STIG
  # refreshes — gated on `converters.write` or admin.
  before_action :authorize_converter_write!, only: [ :refresh_aws_labs ]

  SEVERITY_ORDER = %w[high medium low info].freeze

  def index
    @cdef_documents = CdefDocument.order(created_at: :desc)
    @total_count = @cdef_documents.count
    @controls_count = CdefControl.count
    @completed_count = @cdef_documents.where(status: "completed").count
    @cdef_documents = @cdef_documents.search_text(params[:q]) # #672 — filter listed rows; tiles keep totals
  end

  def show
    return if @cdef_document.pending? || @cdef_document.processing? || @cdef_document.failed?

    controls_scope = @cdef_document.cdef_controls

    @severity_counts = controls_scope.group(:severity).count
    @total_controls  = controls_scope.count

    @heatmap_data, @heatmap_families, @heatmap_severities = build_severity_heatmap(controls_scope)

    @controls = controls_scope.order(:row_order).includes(:cdef_control_fields, :cdef_control_statements)

    # #393: deep-link statement editing via ?statement_id=N
    @editing_statement = CdefControlStatement.joins(cdef_control: :cdef_document)
                                             .find_by(id: params[:statement_id],
                                                      cdef_documents: { id: @cdef_document.id })

    # Baseline gap analysis (when CDEF was created from a profile)
    if @cdef_document.profile_document.present?
      gap_service = CdefBaselineGapService.new(@cdef_document)
      @gap_analysis = gap_service.analyze
      @missing_controls = gap_service.missing_control_details if @gap_analysis&.dig(:missing)&.any?
    end
  end

  def new
    @cdef_document = CdefDocument.new
  end

  def create
    handle_multi_file_upload(:cdef, param_key: :cdef_document)
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

  # DELETE /cdef_documents/bulk_destroy (#629) — admin-only.
  def bulk_destroy
    perform_bulk_destroy(
      model_class:   CdefDocument,
      redirect_path: cdef_documents_path,
      label:         "component definition"
    )
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
      flash[:warning] = "OSCAL export failed schema validation. The export modal below has the specifics."
      redirect_to cdef_document_path(@cdef_document, oscal_validation_failed: 1, oscal_format: "json")
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
    service = OscalComponentDefinitionExportService.new(@cdef_document)
    json_string = params[:skip_validation] ? service.export_unvalidated : service.export
    yaml_data = OscalExportFormatService.to_yaml(json_string)

    audit_log("cdef_document_exported", subject: @cdef_document, metadata: { name: @cdef_document.name, format: "yaml" })
    send_data yaml_data,
              filename:    "#{@cdef_document.name}_oscal_cdef_#{Date.today}.yaml",
              type:        "application/x-yaml",
              disposition: "attachment"
  rescue OscalValidationError => e
    Rails.logger.warn("OSCAL YAML validation failed for CDEF #{@cdef_document.id}: #{e.message.to_s.truncate(300)}")
    flash[:warning] = "OSCAL export failed schema validation. The export modal below has the specifics."
    redirect_to cdef_document_path(@cdef_document, oscal_validation_failed: 1, oscal_format: "yaml")
  end

  def download_xml
    service = OscalComponentDefinitionExportService.new(@cdef_document)
    json_string = params[:skip_validation] ? service.export_unvalidated : service.export
    xml_data = OscalExportFormatService.to_xml(json_string, :component_definition)

    audit_log("cdef_document_exported", subject: @cdef_document, metadata: { name: @cdef_document.name, format: "xml" })
    send_data xml_data,
              filename:    "#{@cdef_document.name}_oscal_cdef_#{Date.today}.xml",
              type:        "application/xml",
              disposition: "attachment"
  rescue OscalValidationError => e
    Rails.logger.warn("OSCAL XML validation failed for CDEF #{@cdef_document.id}: #{e.message.to_s.truncate(300)}")
    flash[:warning] = "OSCAL export failed schema validation. The export modal below has the specifics."
    redirect_to cdef_document_path(@cdef_document, oscal_validation_failed: 1, oscal_format: "xml")
  end

  def update_field
    control_id = params[:control_id]
    field_name = params[:field_name]
    field_value = params[:field_value]

    # #498 slice 2 — wrap the inline-edit mutation in CdefMutationService
    # so a field edit that would corrupt OSCAL gets rolled back.
    CdefMutationService.apply(@cdef_document) do |c|
      CdefUpdateService.new(c).update_field(control_id, field_name, field_value)
    end

    audit_log("cdef_control_updated", subject: @cdef_document,
      metadata: { control_id: control_id, field_name: field_name })

    respond_to do |format|
      format.json { render json: { success: true, control_id: control_id, field_name: field_name, field_value: field_value } }
      format.html do
        flash[:success] = "#{field_name.titleize} updated for #{control_id}"
        redirect_to cdef_document_path(@cdef_document, anchor: "control-#{control_id}")
      end
    end
  rescue ArgumentError, ActiveRecord::RecordNotFound, CdefMutationService::ValidationError => e
    respond_to do |format|
      format.json { render json: { success: false, error: e.message }, status: :unprocessable_entity }
      format.html do
        flash[:error] = e.message
        redirect_to cdef_document_path(@cdef_document)
      end
    end
  end

  def update_metadata
    # #498 slice 2 — route through CdefMutationService so OSCAL
    # validation runs before the metadata change commits.
    CdefMutationService.apply(@cdef_document) do |c|
      c.update!(document_metadata_params)
      c.regenerate_oscal_uuid!
    end
    audit_log("cdef_document_updated", subject: @cdef_document, metadata: { name: @cdef_document.name, metadata_update: true })
    flash[:success] = "Document updated"
    redirect_to cdef_document_path(@cdef_document)
  rescue ActiveRecord::RecordInvalid => e
    flash[:error] = e.record.errors.full_messages.join(", ")
    redirect_to cdef_document_path(@cdef_document)
  rescue CdefMutationService::ValidationError => e
    flash[:error] = "OSCAL validation failed — change rolled back: " + e.message.truncate(200)
    redirect_to cdef_document_path(@cdef_document)
  end

  def copy
    # #498 slice 3 — clone runs through CdefMutationService.build_and_apply
    # so the duplicated CDEF's OSCAL representation is validated before
    # commit. A clone that would produce an invalid OSCAL (corrupted
    # source, missing required fields) rolls back instead of leaving
    # an unusable copy.
    copy = CdefMutationService.build_and_apply do
      duplicated = DocumentDuplicationService.new(@cdef_document).duplicate
      if @cdef_document.aws_labs_source?
        duplicated.update!(cloned_from_id: @cdef_document.id)
      end
      duplicated
    end

    audit_log("cdef_document_copied", subject: copy, metadata: { source_id: @cdef_document.id, source_name: @cdef_document.name, copy_name: copy.name, source_type: @cdef_document.aws_labs_source? ? "aws_labs" : nil }.compact)
    flash[:success] = "Component Definition duplicated as '#{copy.name}'"
    redirect_to cdef_document_path(copy)
  rescue StandardError => e
    # Issue #519 — surface duplication failures in logs + audit + flash
    # instead of a bare 500. AWS Labs CDEFs are the known repro path.
    Rails.logger.error("[cdef_documents#copy] source_id=#{@cdef_document.id} aws_labs=#{@cdef_document.aws_labs_source?} failed: #{e.class}: #{e.message}")
    Rails.logger.error("[cdef_documents#copy] backtrace: " + e.backtrace.first(20).join(" | "))
    audit_log("cdef_document_copy_failed", subject: @cdef_document,
      metadata: { source_id: @cdef_document.id, source_name: @cdef_document.name,
                  source_type: @cdef_document.aws_labs_source? ? "aws_labs" : nil,
                  error_class: e.class.to_s, error_message: e.message.to_s[0, 300] }.compact)
    flash[:error] = "Could not duplicate '#{@cdef_document.name}': #{e.message.to_s[0, 200]}"
    redirect_to cdef_document_path(@cdef_document)
  end

  def select_profile
    @profiles = ProfileDocument.where(lifecycle_status: "published")
                               .where.not(resolved_catalog_json: nil)
                               .includes(:control_catalog)
                               .order(updated_at: :desc)
  end

  def create_from_profile
    profile = ProfileDocument.find_by!(slug: params[:source_profile_id])

    cdef = CdefFromProfileService.new(profile, name: params[:cdef_name]).create

    audit_log("cdef_document_created_from_profile", subject: cdef,
      metadata: { name: cdef.name, source_profile_id: profile.id, source_profile_name: profile.name })
    flash[:success] = "Component Definition '#{cdef.name}' created from profile '#{profile.name}'."
    redirect_to cdef_document_path(cdef)
  rescue ArgumentError => e
    flash[:error] = e.message
    redirect_to select_profile_cdef_documents_path
  rescue ActiveRecord::RecordNotFound
    flash[:error] = "Published profile not found."
    redirect_to select_profile_cdef_documents_path
  end

  # GET /cdef_documents/:id/attach_profile (#628)
  # Profile picker for an EXISTING empty CDEF so a metadata-only shell can
  # gain a control basis instead of being a dead end.
  def attach_profile
    if @cdef_document.cdef_controls.exists?
      flash[:notice] = "This component definition already has controls."
      redirect_to(cdef_document_path(@cdef_document)) and return
    end

    @profiles = ProfileDocument.where(lifecycle_status: "published")
                               .where.not(resolved_catalog_json: nil)
                               .includes(:control_catalog)
                               .order(updated_at: :desc)
  end

  # POST /cdef_documents/:id/populate_from_profile (#628)
  # Populate an existing empty CDEF from a published profile.
  def populate_from_profile
    profile = ProfileDocument.find_by!(slug: params[:source_profile_id])

    CdefFromProfileService.new(profile).populate(@cdef_document)

    audit_log("cdef_document_populated_from_profile", subject: @cdef_document,
      metadata: { name: @cdef_document.name, source_profile_id: profile.id, source_profile_name: profile.name })
    flash[:success] = "Populated '#{@cdef_document.name}' from profile '#{profile.name}'."
    redirect_to cdef_document_path(@cdef_document)
  rescue ArgumentError => e
    flash[:error] = e.message
    redirect_to attach_profile_cdef_document_path(@cdef_document)
  rescue ActiveRecord::RecordNotFound
    flash[:error] = "Published profile not found."
    redirect_to attach_profile_cdef_document_path(@cdef_document)
  end

  # POST /cdef_documents/refresh_aws_labs (#488)
  #
  # Manually trigger an AwsLabsCdefRefreshJob without waiting for the weekly
  # recurring tick. Mirrors the DISA CCI "Refresh Now" button precedent
  # (ConvertersController#refresh_cci). RBAC: converters.write via the
  # before_action above. Feature-flag gated; an in-flight cache lock
  # prevents rapid double-clicks from flooding the queue.
  def refresh_aws_labs
    unless SparcConfig.aws_labs_cdef_enabled?
      redirect_to cdef_documents_path,
        flash: { error: "AWS Labs CDEF ingestion is disabled (set SPARC_AWS_LABS_CDEF_ENABLED=true to enable)." }
      return
    end

    lock_key = "aws_labs_cdef_refresh:in_flight"
    if Rails.cache.exist?(lock_key)
      redirect_to cdef_documents_path,
        flash: { warning: "An AWS Labs CDEF refresh is already in flight. Try again in a few minutes." }
      return
    end
    Rails.cache.write(lock_key, true, expires_in: 5.minutes)

    AwsLabsCdefRefreshJob.perform_later(force: true)
    audit_log("aws_labs_cdef_refresh_requested",
      subject: nil,
      metadata: { triggered_via: "ui", actor_email: current_user&.email })

    redirect_to cdef_documents_path,
      flash: { success: "AWS Labs CDEF refresh queued. New rows will appear once the worker processes them." }
  end

  def status
    render json: {
      status: @cdef_document.status,
      error_message: @cdef_document.error_message
    }
  end

  # PATCH /cdef_documents/:id/update_statement
  # Permits ONLY editable attributes -- statement_id/label/parent_statement_id
  # are read-only references to the catalog (#393).
  def update_statement
    statement = CdefControlStatement.joins(cdef_control: :cdef_document)
                                    .find_by!(id: params[:statement_id],
                                              cdef_documents: { id: @cdef_document.id })

    permitted = params.require(:cdef_control_statement)
                      .permit(*CdefControlStatement::EDITABLE_ATTRIBUTES,
                              set_parameters_data: [])

    # #498 slice 2 — wrap statement edit in CdefMutationService so the
    # post-edit OSCAL is validated. Statement attributes are referenced
    # from components[].control-implementations[]; an edit that
    # violated the schema would silently persist before.
    CdefMutationService.apply(@cdef_document) do |c|
      statement.update!(permitted)
      c.regenerate_oscal_uuid!
    end
    audit_log("cdef_statement_updated", subject: @cdef_document,
              metadata: { statement_id: statement.statement_id })
    flash[:success] = "Statement #{statement.label.presence || statement.statement_id} updated."
    redirect_to cdef_document_path(@cdef_document, anchor: "stmt-#{statement.id}")
  rescue ActiveRecord::RecordInvalid => e
    flash[:error] = e.record.errors.full_messages.join(", ")
    redirect_to cdef_document_path(@cdef_document, anchor: "stmt-#{statement.id}")
  rescue CdefMutationService::ValidationError => e
    flash[:error] = "OSCAL validation failed — change rolled back: " + e.message.truncate(200)
    redirect_to cdef_document_path(@cdef_document, anchor: "stmt-#{statement.id}")
  end

  # ── Control-level resource linking (AJAX) ───────────────────────────

  def create_control_resource
    control = @cdef_document.cdef_controls.find_by!(control_id: params[:control_id])
    resource = BackMatterResource.new(control_resource_params)
    resource.uuid = SecureRandom.uuid
    resource.source = "managed"
    resource.resourceable = @cdef_document
    resource.organization = current_user.organizations.first if current_user.organizations.any?
    resource.globally_available = params.dig(:back_matter_resource, :globally_available) == "1"

    # #498 slice 3 — wrap back-matter writes in CdefMutationService so a
    # resource that would push the OSCAL out of schema is rejected
    # pre-commit. The resource + link create together inside the
    # transaction; ValidationError or save failure rolls both back.
    CdefMutationService.apply(@cdef_document) do |_c|
      resource.save!
      control.control_back_matter_links.create!(back_matter_resource: resource)
      # #581 — emit per-resource audit row alongside the document-level
      # control_resource_created audit_log.
      BackMatterAudit.record_create(resource, user: current_user)
    end

    audit_log("control_resource_created", subject: resource,
              metadata: { control_id: params[:control_id], title: resource.title })
    render json: { success: true, resource: { id: resource.id, uuid: resource.uuid, title: resource.title, href: resource.href } }
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
  rescue CdefMutationService::ValidationError => e
    render json: { success: false, error: "OSCAL validation failed: #{e.message.truncate(200)}" }, status: :unprocessable_entity
  end

  def link_control_resource
    control = @cdef_document.cdef_controls.find_by!(control_id: params[:control_id])
    resource = BackMatterResource.find(params[:back_matter_resource_id])
    link = control.control_back_matter_links.build(back_matter_resource: resource)

    if link.save
      audit_log("control_resource_linked", subject: resource,
                metadata: { control_id: params[:control_id], resource_uuid: resource.uuid })
      render json: { success: true, resource: { id: resource.id, uuid: resource.uuid, title: resource.title } }
    else
      render json: { success: false, error: link.errors.full_messages.join(", ") }, status: :unprocessable_entity
    end
  end

  # ── #499 slice 5 — bulk-apply Converter UI (preview-then-confirm) ──

  # GET /cdef_documents/:id/bulk_apply
  def bulk_apply
    authorize_bulk_apply_web!
    refuse_if_aws_labs!
    @converters = Converter.where(status: "complete").order(:name)
    @baseline_present = @cdef_document.profile_document.present?
  end

  # POST /cdef_documents/:id/bulk_apply_preview
  def bulk_apply_preview
    authorize_bulk_apply_web!
    refuse_if_aws_labs!

    @converter = Converter.find_by(id: params[:converter_id])
    unless @converter
      flash[:error] = "Converter not found"
      return redirect_to(bulk_apply_cdef_document_path(@cdef_document))
    end

    @target_rev = params[:target_rev].presence
    @only_missing_vs_baseline = ActiveModel::Type::Boolean.new.cast(params[:only_missing_vs_baseline])

    @result = CdefBulkApplyService.new(
      cdef:                     @cdef_document,
      converter:                @converter,
      target_rev:               @target_rev,
      only_missing_vs_baseline: @only_missing_vs_baseline
    ).preview

    audit_log("cdef_bulk_apply_converter_previewed", subject: @cdef_document,
              metadata: { converter_id: @converter.id, ready: @result.stats[:ready] })
    render :bulk_apply_preview
  rescue ArgumentError => e
    flash[:error] = e.message
    redirect_to bulk_apply_cdef_document_path(@cdef_document)
  end

  # POST /cdef_documents/:id/bulk_apply_confirm
  def bulk_apply_confirm
    authorize_bulk_apply_web!
    refuse_if_aws_labs!

    selected = params[:selected_target_ids].respond_to?(:to_unsafe_h) ? params[:selected_target_ids].to_unsafe_h : {}

    result = CdefBulkApplyService.apply!(
      cdef:                @cdef_document,
      token:               params[:token].to_s,
      selected_target_ids: selected,
      user:                current_user
    )

    flash[:success] = "Bulk apply complete — added #{result[:added]} control(s)"
    redirect_to cdef_document_path(@cdef_document)
  rescue ArgumentError => e
    flash[:error] = "Apply failed: #{e.message}"
    redirect_to bulk_apply_cdef_document_path(@cdef_document)
  rescue CdefMutationService::ValidationError => e
    flash[:error] = "OSCAL validation failed — apply rolled back: #{e.message.truncate(200)}"
    redirect_to bulk_apply_cdef_document_path(@cdef_document)
  end

  def unlink_control_resource
    control = @cdef_document.cdef_controls.find_by!(control_id: params[:control_id])
    link = control.control_back_matter_links.find(params[:link_id])
    audit_log("control_resource_unlinked", subject: link.back_matter_resource,
              metadata: { control_id: params[:control_id] })
    link.destroy
    render json: { success: true }
  end

  private

  # #499 slice 5 — bulk-apply web UI auth helpers.
  def authorize_bulk_apply_web!
    return if current_user&.admin?
    return if current_user&.has_permission?("converters.write")

    flash[:error] = "Not authorized to bulk-apply converters."
    redirect_to cdef_document_path(@cdef_document) and return
  end

  def refuse_if_aws_labs!
    return unless @cdef_document.aws_labs_source?

    flash[:error] = "Bulk-apply is disabled on AWS-Labs-sourced CDEFs. Clone first."
    redirect_to cdef_document_path(@cdef_document) and return
  end

  def control_resource_params
    params.require(:back_matter_resource).permit(:title, :description, :href, :media_type, :rel)
  end

  def document_metadata_params
    permitted = params.require(:cdef_document).permit(:name, :cdef_version, :oscal_version, :description)
    merge_metadata_extra(permitted, :cdef_document)
  end

  def set_cdef_document
    @cdef_document = CdefDocument.find_by!(slug: params[:id])
  end

  # OscalExportable hooks
  def oscal_export_document = @cdef_document
  def oscal_export_service(doc) = OscalComponentDefinitionExportService.new(doc)
  def oscal_document_type_label = "Component Definition"

  def publish_config
    { document: @cdef_document, audit_event: "cdef_document_published",
      redirect_path: cdef_document_path(@cdef_document), label: "CDEF" }
  end

  # Issue #488 — matches the wrapper of the same name in
  # ConvertersController so the AWS Labs catalog-refresh action sits in
  # the same RBAC bucket as the DISA CCI / STIG refresh actions
  # (`converters.write` or admin).
  def authorize_converter_write!
    authorize_permission!("converters.write")
  end

  def ensure_editable!
    # Issue #466 — AWS Labs-sourced CDEFs are read-only. Users clone them
    # via the existing copy action to make changes. The clone records
    # cloned_from_id so refreshes never touch it.
    if @cdef_document.aws_labs_source?
      flash[:error] = "This component definition was imported from AWS Labs and is read-only. Use 'Copy' to create an editable clone."
      redirect_to cdef_document_path(@cdef_document) and return
    end

    return unless @cdef_document.published_lifecycle?

    flash[:error] = "This component definition is published and read-only. Create a copy to make changes."
    redirect_to cdef_document_path(@cdef_document)
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
