class SapDocumentsController < ApplicationController
  include FileUploadable
  include Publishable
  include OscalExportable

  before_action :set_sap_document, only: %i[
    show edit update destroy download_json download_oscal
    download_oscal_validated download_oscal_unvalidated
    download_yaml download_xml validate_oscal_export status
    update_metadata publish publish_check associate_source update_objective
  ]
  before_action :ensure_editable!, only: [ :update, :update_metadata, :publish, :update_objective ]

  METHOD_ORDER = %w[examine interview test].freeze

  def index
    @sap_documents = SapDocument.order(created_at: :desc)
    @total_count = @sap_documents.count
    @controls_count = SapControl.count
    @completed_count = @sap_documents.where(status: "completed").count
  end

  def show
    return if @sap_document.pending? || @sap_document.processing? || @sap_document.failed?

    controls_scope = @sap_document.sap_controls

    @method_counts, @multiple_count = compute_method_counts(controls_scope)
    @status_counts = controls_scope.group(:assessment_status).count
    @total_controls = controls_scope.count

    @heatmap_data, @heatmap_families, @heatmap_methods = build_method_heatmap(controls_scope)

    # N+1 guard: include objectives so the view can render the nested table
    # and roll up per-control status without firing extra queries per card.
    @controls = controls_scope.order(:row_order)
                              .includes(:sap_control_fields, :sap_control_objectives)

    # Status (objective rollup) heatmap by family. Independent of the methods
    # heatmap so users can see assessment progress separately from coverage.
    @status_heatmap_data, @status_heatmap_families, @status_heatmap_statuses =
      build_objective_status_heatmap(@controls)

    # Group controls by family for collapsible display
    @controls_by_family = @controls.group_by { |c|
      c.control_family.presence || c.control_id.to_s.split("-").first.upcase
    }
    @sorted_families = @controls_by_family.keys.sort

    # Build family name lookup from catalog
    @family_names = {}
    family_codes = @sorted_families.map(&:downcase)
    ControlFamily.where(code: family_codes).each { |f| @family_names[f.code] = f.name }

    # Allow ?objective_id=N to deep-link to an objective edit modal.
    @editing_objective = SapControlObjective.joins(sap_control: :sap_document)
                                            .find_by(id: params[:objective_id],
                                                     sap_documents: { id: @sap_document.id })
    @needs_reassociation = @sap_document.import_metadata&.dig(
      ControlObjectiveExtractorService::REASSOCIATION_FLAG
    ) == ControlObjectiveExtractorService::REASSOCIATION_VALUE
  end

  def new
    @sap_document = SapDocument.new
    @ssp_documents = SspDocument.where(status: "completed").order(:name)
    @profile_documents = ProfileDocument.where(status: "completed").order(:name)
  end

  def create
    if params[:sap_document]&.key?(:file) && params[:sap_document][:file].present?
      handle_multi_file_upload(:sap, param_key: :sap_document)
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
      :objective, :test_case,
      assessment_methods: []
    )

    # Multi-select checkbox group sends assessment_methods as an array.
    # Stored as comma-separated values in the assessment_method column.
    if permitted.key?(:assessment_methods)
      methods = Array(permitted.delete(:assessment_methods)).reject(&:blank?).map(&:downcase).uniq
      permitted[:assessment_method] = methods.join(",")
    end

    if control.update(permitted)
      @sap_document.regenerate_oscal_uuid!
      flash[:success] = "Control #{control.control_id} updated"
    else
      flash[:error] = control.errors.full_messages.join(", ")
    end
    redirect_to sap_document_path(@sap_document)
  end

  def destroy
    name = @sap_document.name
    if @sap_document.destroy
      audit_log("sap_document_deleted", subject: @sap_document, metadata: { name: name })
      flash[:success] = "Assessment Plan '#{name}' deleted."
      redirect_to sap_documents_path
    else
      audit_log("sap_document_delete_blocked", subject: @sap_document,
        metadata: { name: name, reason: @sap_document.errors.full_messages.join(", ") })
      flash[:error] = @sap_document.errors.full_messages.join(", ")
      redirect_to sap_document_path(@sap_document)
    end
  end

  def download_json
    json_data = JsonExportService.export_sap(@sap_document)

    audit_log("sap_document_exported", subject: @sap_document, metadata: { name: @sap_document.name, format: "json" })
    send_data json_data,
              filename:    "#{@sap_document.name}_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_oscal
    service = OscalAssessmentPlanExportService.new(@sap_document)
    result = service.validation_result

    if result.valid?
      audit_log("sap_document_exported", subject: @sap_document, metadata: { name: @sap_document.name, format: "oscal" })
      send_data service.export,
                filename:    "#{@sap_document.name}_oscal_sap_#{Date.today}.json",
                type:        "application/json",
                disposition: "attachment"
    else
      Rails.logger.warn("OSCAL validation failed for SAP #{@sap_document.id}: #{result.errors.first(3).join('; ')}")
      flash[:warning] = "OSCAL export failed schema validation. The export modal below has the specifics."
      redirect_to sap_document_path(@sap_document, oscal_validation_failed: 1, oscal_format: "json")
    end
  end

  def download_oscal_validated
    service = OscalAssessmentPlanExportService.new(@sap_document)
    oscal_data = service.export

    audit_log("sap_document_exported", subject: @sap_document, metadata: { name: @sap_document.name, format: "oscal_validated" })
    send_data oscal_data,
              filename:    "#{@sap_document.name}_oscal_assessment-plan_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_oscal_unvalidated
    service = OscalAssessmentPlanExportService.new(@sap_document)
    oscal_data = service.export_unvalidated

    audit_log("sap_document_exported", subject: @sap_document, metadata: { name: @sap_document.name, format: "oscal_unvalidated" })
    send_data oscal_data,
              filename:    "#{@sap_document.name}_oscal_assessment-plan_unvalidated_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_yaml
    service = OscalAssessmentPlanExportService.new(@sap_document)
    json_string = params[:skip_validation] ? service.export_unvalidated : service.export
    yaml_data = OscalExportFormatService.to_yaml(json_string)

    audit_log("sap_document_exported", subject: @sap_document, metadata: { name: @sap_document.name, format: "yaml" })
    send_data yaml_data,
              filename:    "#{@sap_document.name}_oscal_sap_#{Date.today}.yaml",
              type:        "application/x-yaml",
              disposition: "attachment"
  rescue OscalValidationError => e
    Rails.logger.warn("OSCAL YAML validation failed for SAP #{@sap_document.id}: #{e.message.to_s.truncate(300)}")
    flash[:warning] = "OSCAL export failed schema validation. The export modal below has the specifics."
    redirect_to sap_document_path(@sap_document, oscal_validation_failed: 1, oscal_format: "yaml")
  end

  def download_xml
    service = OscalAssessmentPlanExportService.new(@sap_document)
    json_string = params[:skip_validation] ? service.export_unvalidated : service.export
    xml_data = OscalExportFormatService.to_xml(json_string, :assessment_plan)

    audit_log("sap_document_exported", subject: @sap_document, metadata: { name: @sap_document.name, format: "xml" })
    send_data xml_data,
              filename:    "#{@sap_document.name}_oscal_sap_#{Date.today}.xml",
              type:        "application/xml",
              disposition: "attachment"
  rescue OscalValidationError => e
    Rails.logger.warn("OSCAL XML validation failed for SAP #{@sap_document.id}: #{e.message.to_s.truncate(300)}")
    flash[:warning] = "OSCAL export failed schema validation. The export modal below has the specifics."
    redirect_to sap_document_path(@sap_document, oscal_validation_failed: 1, oscal_format: "xml")
  end

  def update_metadata
    if @sap_document.update(document_metadata_params)
      @sap_document.regenerate_oscal_uuid!
      audit_log("sap_document_updated", subject: @sap_document, metadata: { name: @sap_document.name, metadata_update: true })
      flash[:success] = "Document updated"
    else
      flash[:error] = @sap_document.errors.full_messages.join(", ")
    end
    redirect_to sap_document_path(@sap_document)
  end

  # Associate SAP with a profile and/or SSP, then build controls directly
  # from the linked source. Does NOT require the original OSCAL file to
  # be attached (which may have been cleaned up after async processing).
  def associate_source
    profile_id = params.dig(:sap_document, :profile_document_id)
    ssp_id = params.dig(:sap_document, :ssp_document_id)

    @sap_document.update!(
      profile_document_id: profile_id.presence,
      ssp_document_id: ssp_id.presence
    )

    # Resolve control IDs from the linked source (priority: profile > SSP profile > SSP controls)
    control_ids = []
    if profile_id.present?
      profile = ProfileDocument.find_by(id: profile_id)
      control_ids = profile.profile_controls.pluck(:control_id) if profile
    end
    if control_ids.empty? && ssp_id.present?
      ssp = SspDocument.find_by(id: ssp_id)
      if ssp&.profile_document_id.present?
        profile = ProfileDocument.find_by(id: ssp.profile_document_id)
        control_ids = profile.profile_controls.pluck(:control_id) if profile
      end
      if control_ids.empty? && ssp
        control_ids = ssp.ssp_controls.where.not(control_id: nil).pluck(:control_id).uniq
      end
    end

    if control_ids.empty?
      flash[:error] = "Source associated but no controls found in linked profile/SSP."
      redirect_to sap_document_path(@sap_document) and return
    end

    # Build per-control assessment-method map (comma-separated). Objectives
    # come from ControlObjectiveExtractorService below.
    method_map = build_assessment_method_map(profile_id, ssp_id)

    # Replace existing controls + objectives. Wrap in a transaction so a
    # mid-rebuild failure can't leave the document in a half-rebuilt state.
    objective_count = 0
    ApplicationRecord.transaction do
      @sap_document.sap_controls.delete_all  # cascades to objectives
      control_ids.each_with_index do |control_id, idx|
        denormalized_id = control_id.to_s.upcase.gsub(".", " (").then { |s| s.include?("(") ? "#{s})" : s }
        methods = (method_map[control_id.to_s.downcase] || []).map(&:downcase).uniq
        @sap_document.sap_controls.create!(
          control_id: denormalized_id,
          assessment_method: methods.join(","),
          assessment_status: "planned",
          row_order: idx
        )
      end
      objective_count = ControlObjectiveExtractorService.new(@sap_document).backfill!
    end

    bm_count = copy_back_matter_from_source(profile_id, ssp_id)

    audit_log("sap_document_reprocessed", subject: @sap_document,
              metadata: { profile_id: profile_id, ssp_id: ssp_id,
                          controls_assigned: control_ids.size,
                          objectives_assigned: objective_count,
                          back_matter_copied: bm_count })
    msg = "Source associated. #{control_ids.size} controls assigned."
    msg += " #{objective_count} objectives populated." if objective_count > 0
    msg += " #{bm_count} back-matter resources copied." if bm_count > 0
    flash[:success] = msg
    redirect_to sap_document_path(@sap_document)
  rescue StandardError => e
    flash[:error] = "Failed to associate: #{e.message}"
    redirect_to sap_document_path(@sap_document)
  end

  # PATCH /sap_documents/:id/update_objective
  # Body: { objective_id, sap_control_objective: { status, assessor_name, assessor_notes } }
  def update_objective
    objective = SapControlObjective.joins(sap_control: :sap_document)
                                   .find_by!(id: params[:objective_id],
                                             sap_documents: { id: @sap_document.id })

    permitted = params.require(:sap_control_objective)
                      .permit(:status, :assessor_name, :assessor_notes)

    if permitted[:status] == "passing" || permitted[:status] == "failed"
      permitted[:assessed_at] = Time.current
    end

    if objective.update(permitted)
      @sap_document.regenerate_oscal_uuid!
      audit_log("sap_objective_updated", subject: @sap_document,
                metadata: { objective_id: objective.objective_id, status: objective.status })
      flash[:success] = "Objective #{objective.label.presence || objective.objective_id} updated."
    else
      flash[:error] = objective.errors.full_messages.join(", ")
    end
    redirect_to sap_document_path(@sap_document, anchor: "obj-#{objective.id}")
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
    @sap_document = SapDocument.find_by!(slug: params[:id])
  end

  # Build a map of control_id => [methods] from the linked profile/SSP
  # resolved catalog JSON. Objectives are no longer extracted here -- they
  # are populated by ControlObjectiveExtractorService into discrete
  # SapControlObjective records.
  def build_assessment_method_map(profile_id, ssp_id)
    catalog_json = nil
    if profile_id.present?
      profile = ProfileDocument.find_by(id: profile_id)
      catalog_json = profile&.resolved_catalog_json
    end
    if catalog_json.blank? && ssp_id.present?
      ssp = SspDocument.find_by(id: ssp_id)
      profile = ProfileDocument.find_by(id: ssp.profile_document_id) if ssp&.profile_document_id.present?
      catalog_json = profile&.resolved_catalog_json
    end
    return {} if catalog_json.blank?

    methods_map = {}
    catalog = catalog_json.is_a?(Hash) ? (catalog_json["catalog"] || catalog_json) : {}
    extract_methods_from_groups(catalog["groups"] || [], methods_map)
    extract_methods_from_controls(catalog["controls"] || [], methods_map)
    methods_map
  end

  def extract_methods_from_groups(groups, methods_map)
    groups.each do |group|
      extract_methods_from_controls(group["controls"] || [], methods_map)
      extract_methods_from_groups(group["groups"] || [], methods_map)
    end
  end

  def extract_methods_from_controls(controls, methods_map)
    controls.each do |ctrl|
      methods = []
      walk_method_parts(ctrl["parts"] || [], methods)
      if methods.any? && ctrl["id"].present?
        methods_map[ctrl["id"].to_s.downcase] = methods.uniq
      end
      extract_methods_from_controls(ctrl["controls"] || [], methods_map)
    end
  end

  def walk_method_parts(parts, methods)
    parts.each do |part|
      if part["name"] == "assessment-method"
        method_prop = (part["props"] || []).find { |p| p["name"] == "method" }
        methods << method_prop["value"] if method_prop && method_prop["value"].present?
      end
      walk_method_parts(part["parts"] || [], methods)
    end
  end

  # Copy back-matter resources from the linked profile and/or SSP to this SAP.
  # Reads from BOTH back_matter_resources table (managed) AND
  # import_metadata["back_matter"] (imported from OSCAL).
  # Skips resources whose UUIDs are already present (idempotent re-runs).
  # Returns the count of new resources copied.
  def copy_back_matter_from_source(profile_id, ssp_id)
    sources = []
    sources << ProfileDocument.find_by(id: profile_id) if profile_id.present?
    if ssp_id.present?
      ssp = SspDocument.find_by(id: ssp_id)
      sources << ssp if ssp
      sources << ProfileDocument.find_by(id: ssp.profile_document_id) if ssp&.profile_document_id.present?
    end
    sources.compact!

    existing_uuids = @sap_document.back_matter_resources.pluck(:uuid).to_set
    copied = 0

    sources.each do |source|
      # 1. Copy managed BackMatterResource records
      source.back_matter_resources.each do |src_bm|
        next if existing_uuids.include?(src_bm.uuid)
        @sap_document.back_matter_resources.create!(
          uuid:          src_bm.uuid,
          title:         src_bm.title,
          description:   src_bm.description,
          rel:           src_bm.rel,
          media_type:    src_bm.media_type,
          href:          src_bm.href,
          source:        "imported",
          resource_data: src_bm.resource_data
        )
        existing_uuids << src_bm.uuid
        copied += 1
      end

      # 2. Copy imported back-matter from import_metadata (OSCAL JSON hashes)
      imported = source.respond_to?(:import_metadata) ? (source.import_metadata&.dig("back_matter") || []) : []
      imported.each do |bm_hash|
        uuid = bm_hash["uuid"]
        next if uuid.blank? || existing_uuids.include?(uuid)
        rlink = (bm_hash["rlinks"] || []).first || {}
        @sap_document.back_matter_resources.create!(
          uuid:          uuid,
          title:         bm_hash["title"] || "Imported Resource",
          description:   bm_hash["description"],
          rel:           "reference",
          media_type:    rlink["media-type"],
          href:          rlink["href"],
          source:        "imported",
          resource_data: bm_hash.except("uuid", "title", "description", "rlinks")
        )
        existing_uuids << uuid
        copied += 1
      rescue ActiveRecord::RecordInvalid => e
        Rails.logger.warn("Skipping invalid imported back-matter resource #{uuid}: #{e.message}")
      end
    end

    copied
  end

  # OscalExportable hooks
  def oscal_export_document = @sap_document
  def oscal_export_service(doc) = OscalAssessmentPlanExportService.new(doc)
  def oscal_document_type_label = "Assessment Plan"

  def publish_config
    { document: @sap_document, audit_event: "sap_document_published",
      redirect_path: sap_document_path(@sap_document), label: "SAP" }
  end

  def ensure_editable!
    return unless @sap_document.published_lifecycle?

    flash[:error] = "This assessment plan is published and read-only. Create a copy to make changes."
    redirect_to sap_document_path(@sap_document)
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

      audit_log("sap_document_created", subject: sap, metadata: { name: sap.name, creation_method: "wizard" })
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

  # Counts each assigned method individually (a control with "examine,interview"
  # adds 1 to each) plus a separate "multiple" tally for controls that have
  # 2+ methods. Returns [counts_hash, multiple_count].
  def compute_method_counts(scope)
    counts = Hash.new(0)
    multiple = 0
    scope.pluck(:assessment_method).each do |raw|
      methods = raw.to_s.split(",").map { |m| m.strip.downcase }.reject(&:blank?).uniq
      if methods.empty?
        counts[nil] += 1
      else
        multiple += 1 if methods.size > 1
        methods.each { |m| counts[m] += 1 }
      end
    end
    [ counts, multiple ]
  end

  # Heatmap counts each method per family individually (so multi-method
  # controls contribute to multiple cells), plus a "multiple" column
  # showing how many controls in the family have 2+ methods.
  def build_method_heatmap(scope)
    data = {}
    scope.where.not(control_family: [ nil, "" ])
         .pluck(:control_family, :assessment_method).each do |family, raw|
      methods = raw.to_s.split(",").map { |m| m.strip.downcase }.reject(&:blank?).uniq
      data[family] ||= Hash.new(0)
      if methods.empty?
        data[family]["(None)"] += 1
      else
        data[family]["multiple"] += 1 if methods.size > 1
        methods.each { |m| data[family][m] += 1 }
      end
    end

    families = data.keys.sort
    all_methods = data.values.flat_map(&:keys).uniq
    ordered = METHOD_ORDER.select { |m| all_methods.include?(m) }
    ordered << "multiple" if all_methods.include?("multiple")
    ordered += (all_methods - METHOD_ORDER - [ "multiple" ]).sort

    [ data, families, ordered ]
  end

  # Aggregates objective_status_rollup per control_family. Counts each
  # control once under its rolled-up status. Controls without objectives
  # land in the "not_assessed" bucket.
  STATUS_ORDER = %w[failed in-progress pending passing not_applicable not_assessed].freeze

  def build_objective_status_heatmap(controls)
    data = {}
    controls.each do |ctrl|
      family = ctrl.control_family.presence || ctrl.control_id.to_s.split("-").first.upcase
      next if family.blank?
      data[family] ||= Hash.new(0)
      data[family][ctrl.objective_status_rollup] += 1
    end

    families = data.keys.sort
    all_statuses = data.values.flat_map(&:keys).uniq
    ordered = STATUS_ORDER.select { |s| all_statuses.include?(s) }
    ordered += (all_statuses - STATUS_ORDER).sort

    [ data, families, ordered ]
  end
end
