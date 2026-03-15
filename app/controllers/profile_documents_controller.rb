class ProfileDocumentsController < ApplicationController
  include FileUploadable
  skip_before_action :require_authentication, only: [ :index, :show ]

  before_action :set_profile_document, only: %i[
    show destroy download_json download_oscal
    download_oscal_validated download_oscal_unvalidated
    download_yaml download_xml status
    update_metadata copy publish publish_check download_resolved_catalog
    manage_controls update_controls
  ]
  before_action :ensure_editable!, only: %i[update_metadata update_controls publish]

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

    # Group controls by family for collapsible display
    @controls_by_family = @controls.group_by { |c|
      c.control_family.presence || c.control_id.to_s.split("-").first.upcase
    }
    @sorted_families = @controls_by_family.keys.sort

    # Build family name lookup, sub-parts map, and sort ordering from the catalog
    @family_names = {}
    @catalog_sub_parts = {}
    @sort_id_map = {}

    if @profile_document.control_catalog.present?
      catalog = @profile_document.control_catalog
      catalog.control_families.each { |f| @family_names[f.code] = f.name }

      profile_control_ids = @controls.map(&:control_id).to_set
      sorted_parent_ids = profile_control_ids.sort_by { |id| -id.length }

      catalog.catalog_controls.includes(:control_family).each do |cc|
        @sort_id_map[cc.control_id] = cc.sort_id if cc.sort_id.present?
        next if profile_control_ids.include?(cc.control_id)

        # Sub-parts start with a parent ID followed by a lowercase letter (e.g., ac-1a, ac-1a.1)
        parent = sorted_parent_ids.find { |pid|
          cc.control_id.start_with?(pid) &&
          cc.control_id.length > pid.length &&
          cc.control_id[pid.length]&.match?(/[a-z]/)
        }

        if parent
          @catalog_sub_parts[parent] ||= []
          @catalog_sub_parts[parent] << cc
        end
      end
    end
  end

  def new
    @profile_document = ProfileDocument.new
  end

  def create
    handle_file_upload(:profile, param_key: :profile_document)
  end

  def destroy
    name = @profile_document.name
    if @profile_document.destroy
      audit_log("profile_document_deleted", subject: @profile_document, metadata: { name: name })
      flash[:success] = "Profile '#{name}' deleted."
      redirect_to profile_documents_path
    else
      audit_log("profile_document_delete_blocked", subject: @profile_document,
        metadata: { name: name, reason: @profile_document.errors.full_messages.join(", ") })
      flash[:error] = @profile_document.errors.full_messages.join(", ")
      redirect_to profile_document_path(@profile_document)
    end
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

  def download_yaml
    json_string = OscalProfileExportService.new(@profile_document).export
    yaml_data = OscalExportFormatService.to_yaml(json_string)

    audit_log("profile_document_exported", subject: @profile_document, metadata: { name: @profile_document.name, format: "yaml" })
    send_data yaml_data,
              filename:    "#{@profile_document.name}_oscal_profile_#{Date.today}.yaml",
              type:        "application/x-yaml",
              disposition: "attachment"
  end

  def download_xml
    json_string = OscalProfileExportService.new(@profile_document).export
    xml_data = OscalExportFormatService.to_xml(json_string, :profile)

    audit_log("profile_document_exported", subject: @profile_document, metadata: { name: @profile_document.name, format: "xml" })
    send_data xml_data,
              filename:    "#{@profile_document.name}_oscal_profile_#{Date.today}.xml",
              type:        "application/xml",
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

  def publish_check
    service = PublicationValidationService.new(@profile_document, current_user: current_user)
    render json: service.publication_readiness
  end

  def publish
    unless @profile_document.control_catalog
      flash[:error] = "Cannot publish: no source catalog linked to this profile."
      redirect_to profile_document_path(@profile_document) and return
    end

    # Apply any inline metadata fixes from the publish modal
    apply_profile_metadata_fixes!(@profile_document) if params[:metadata_fixes].present?

    # Validate publication metadata
    validation = PublicationValidationService.new(@profile_document, current_user: current_user)
    result = validation.validate
    unless result.valid?
      flash[:error] = "Cannot publish: #{result.errors.join('; ')}"
      redirect_to profile_document_path(@profile_document) and return
    end

    service = OscalResolvedProfileCatalogService.new(@profile_document)
    resolved_json = service.export

    @profile_document.update!(
      published: Time.current.utc.iso8601,
      lifecycle_status: "published",
      resolved_catalog_json: JSON.parse(resolved_json)
    )

    audit_log("profile_document_published", subject: @profile_document,
              metadata: { name: @profile_document.name, lifecycle_status: "published" })
    flash[:success] = "Profile published. Resolved catalog is now available for download."
    redirect_to profile_document_path(@profile_document)
  end

  def download_resolved_catalog
    if @profile_document.resolved_catalog_json.blank?
      flash[:error] = "No resolved catalog available. Publish the profile first."
      redirect_to profile_document_path(@profile_document) and return
    end

    json_data = JSON.pretty_generate(@profile_document.resolved_catalog_json)
    audit_log("profile_document_exported", subject: @profile_document,
              metadata: { name: @profile_document.name, format: "resolved_catalog" })
    send_data json_data,
              filename:    "#{@profile_document.name}_resolved_catalog_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def select_catalog
    @catalogs = ControlCatalog.order(:name)
  end

  def create_from_catalog
    catalog = ControlCatalog.find_by!(slug: params[:catalog_id])
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
      lifecycle_status: "started",
      description: "Created from #{catalog.name} catalog"
    )

    catalog_controls = catalog.catalog_controls.where(control_id: control_ids).includes(:control_family)
    catalog_controls.each_with_index do |cc, idx|
      pc = profile.profile_controls.create!(
        control_id: cc.control_id,
        title: cc.title,
        control_family: cc.control_family&.code || cc.family_code,
        row_order: idx
      )

      # Inherit parameter definitions from catalog (including parent-control params
      # referenced by sub-controls via {{ insert: param, ... }} template markup)
      cc.effective_params_list.each do |param|
        label = param["label"].to_s
        pc.profile_control_fields.create!(field_name: "parameter:#{param['id']}", field_value: label)
        pc.profile_control_fields.create!(field_name: "parameter_label:#{param['id']}", field_value: label)
      end
    end

    audit_log("profile_document_created", subject: profile, metadata: { name: profile.name, creation_method: "catalog" })
    flash[:success] = "Profile created with #{profile.profile_controls.count} controls from #{catalog.name}"
    redirect_to profile_document_path(profile)
  end

  def manage_controls
    unless @profile_document.control_catalog
      flash[:error] = "Cannot manage controls: no source catalog linked to this profile."
      redirect_to profile_document_path(@profile_document) and return
    end

    @catalog = @profile_document.control_catalog
    @families = @catalog.control_families.includes(:catalog_controls).order(:sort_order, :code)
    # Both profile controls and catalog controls now use the same OSCAL canonical id format.
    @existing_control_ids = @profile_document.profile_controls.pluck(:control_id).to_set
  end

  def update_controls
    unless @profile_document.control_catalog
      flash[:error] = "Cannot update controls: no source catalog linked."
      redirect_to profile_document_path(@profile_document) and return
    end

    desired_ids = Array(params[:control_ids]).reject(&:blank?).to_set
    existing_ids = @profile_document.profile_controls.pluck(:control_id).to_set

    to_add    = desired_ids - existing_ids
    to_remove = existing_ids - desired_ids

    ActiveRecord::Base.transaction do
      if to_remove.any?
        @profile_document.profile_controls.where(control_id: to_remove.to_a).delete_all
      end

      if to_add.any?
        catalog_controls = @profile_document.control_catalog
                            .catalog_controls
                            .where(control_id: to_add.to_a)
                            .includes(:control_family)
        max_order = @profile_document.profile_controls.maximum(:row_order) || 0

        catalog_controls.each_with_index do |cc, idx|
          pc = @profile_document.profile_controls.create!(
            control_id: cc.control_id,
            title: cc.title,
            control_family: cc.control_family&.code || cc.family_code,
            row_order: max_order + idx + 1
          )

          cc.effective_params_list.each do |param|
            label = param["label"].to_s
            pc.profile_control_fields.create!(field_name: "parameter:#{param['id']}", field_value: label)
            pc.profile_control_fields.create!(field_name: "parameter_label:#{param['id']}", field_value: label)
          end
        end
      end
    end

    audit_log("profile_controls_bulk_updated", subject: @profile_document,
              metadata: { added: to_add.size, removed: to_remove.size })
    flash[:success] = "Controls updated: #{to_add.size} added, #{to_remove.size} removed"
    redirect_to profile_document_path(@profile_document)
  end

  def status
    render json: {
      status: @profile_document.status,
      error_message: @profile_document.error_message
    }
  end

  private

  def apply_profile_metadata_fixes!(doc)
    fixes = params[:metadata_fixes]
    return if fixes.blank?

    extra = doc.metadata_extra || {}

    if fixes[:roles].present?
      new_roles = JSON.parse(fixes[:roles]) rescue []
      existing = extra["roles"] || []
      combined = {}
      existing.each { |e| combined[e["id"]] = e }
      new_roles.each { |e| combined[e["id"]] = e }
      extra["roles"] = combined.values if combined.values.any?
    end

    if fixes[:parties].present?
      new_parties = JSON.parse(fixes[:parties]) rescue []
      existing = extra["parties"] || []
      combined = {}
      existing.each { |e| combined[e["uuid"]] = e }
      new_parties.each { |e| combined[e["uuid"]] = e }
      extra["parties"] = combined.values if combined.values.any?
    end

    if fixes[:responsible_parties].present?
      new_rps = JSON.parse(fixes[:responsible_parties]) rescue []
      existing = extra["responsible-parties"] || []
      combined = {}
      existing.each { |e| combined[e["role-id"]] = e }
      new_rps.each { |e| combined[e["role-id"]] = e }
      extra["responsible-parties"] = combined.values if combined.values.any?
    end

    doc.update!(metadata_extra: extra) if extra != doc.metadata_extra
  end

  def document_metadata_params
    permitted = params.require(:profile_document).permit(:name, :profile_version, :oscal_version, :description, :published)
    merge_metadata_extra(permitted, :profile_document)
  end

  def set_profile_document
    @profile_document = ProfileDocument.find_by!(slug: params[:id])
  end

  def ensure_editable!
    return unless @profile_document.published_lifecycle?

    flash[:error] = "This profile is published and read-only. Create a copy to make changes."
    redirect_to profile_document_path(@profile_document)
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
