class ProfileDocumentsController < ApplicationController
  include ReconciliationGate
  # #911 layer 2 — refuse an edit until the document names the baseline
  # its controls descend from. `set_baseline` is deliberately absent.
  before_action :enforce_reconciliation_gate!, only: %i[update_metadata update_controls]
  include BaselineDeclarable
  include CollectionViewable
  include FileUploadable
  include Publishable
  include OscalExportable
  include DocumentApprovalActions
  # #726/#974 — public read when SPARC_PUBLIC_CATALOGS=true, authenticated otherwise.
  # #974 — downloads follow the screens (see ControlCatalogsController).
  public_controls_read only: [ :index, :show,
                               :download_json, :download_oscal, :download_oscal_validated,
                               :download_oscal_unvalidated, :download_yaml, :download_xml,
                               :download_resolved_catalog ]
  # #726: public reads are gated by SPARC_PUBLIC_CATALOGS (secure-by-default). (AC-3)

  before_action :set_profile_document, only: %i[set_baseline
    show destroy download_json download_oscal
    download_oscal_validated download_oscal_unvalidated
    download_yaml download_xml validate_oscal_export status
    update_metadata copy publish publish_check download_resolved_catalog
    manage_controls update_controls
    submit_for_review approve reject
  ]
  before_action :ensure_editable!, only: %i[update_metadata update_controls publish submit_for_review]

  # #919 — this controller had NO authorization on any mutating action.
  # `ensure_editable!` above is a lifecycle-state check and
  # `require_authentication_unless_public_controls` is authentication; neither
  # asks whether the caller may write. Its own Api::V1 sibling already gated the
  # same actions and carried a comment noting the web side did not, so the two
  # surfaces disagreed on the identical operation.
  #
  # Mirrors Api::V1::ProfileDocumentsController#authorize_profiles_write! —
  # unscoped `profiles.write`, because profiles and catalogs are instance-level
  # rather than boundary-scoped. `approve`/`reject` are intentionally excluded:
  # DocumentApprovalActions gates those on approver authority and separation of
  # duties, which is a stricter and different question from write access.
  #
  # NIST AC-3 (access enforcement), AC-6 (least privilege).
  before_action :authorize_profiles_write!, only: %i[
    new create destroy update_metadata copy set_baseline
    select_catalog select_profile create_from_profile create_from_catalog
    manage_controls update_controls publish submit_for_review
  ]

  PRIORITY_ORDER = %w[P1 P2 P3].freeze

  def index
    scope = ProfileDocument.order(created_at: :desc)
    @total_count = scope.count
    # #967 — see ssp_documents_controller. Measured +10 on a demo instance.
    @controls_count = ProfileControl.where(profile_document_id: scope.reorder(nil).select(:id)).count
    @completed_count = scope.where(status: "completed").count

    # #672 search + #908 facets, both through the shared query object so this
    # screen and Api::V1 narrow the collection identically.
    query = ProfileBrowseQuery.new(params, scope: scope)
    @filter_fields = query.filter_fields
    @facets = active_facets(ProfileBrowseQuery.facet_params, labels: ProfileBrowseQuery.facet_labels)
    @clear_facets = clear_facets_params(ProfileBrowseQuery.facet_params)

    # #888 — cards by default, remembered per screen, and paginated.
    @view_mode = resolve_view_mode(:profile_documents)
    @pagy, @profile_documents = paginate_collection(query.records)
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
    handle_multi_file_upload(:profile, param_key: :profile_document)
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
              type:        JSON_CONTENT_TYPE,
              disposition: "attachment"
  end

  def download_oscal
    service = OscalProfileExportService.new(@profile_document)
    result = service.validation_result

    if result.valid?
      audit_log("profile_document_exported", subject: @profile_document, metadata: { name: @profile_document.name, format: "oscal" })
      send_data service.export,
                filename:    "#{@profile_document.name}_oscal_profile_#{Date.today}.json",
                type:        JSON_CONTENT_TYPE,
                disposition: "attachment"
    else
      Rails.logger.warn("OSCAL validation failed for Profile #{@profile_document.id}: #{result.errors.first(3).join('; ')}")
      flash[:warning] = SCHEMA_VALIDATION_FAILED_FLASH
      redirect_to profile_document_path(@profile_document, oscal_validation_failed: 1, oscal_format: "json")
    end
  end

  def download_oscal_validated
    service = OscalProfileExportService.new(@profile_document)
    oscal_data = service.export

    audit_log("profile_document_exported", subject: @profile_document, metadata: { name: @profile_document.name, format: "oscal_validated" })
    send_data oscal_data,
              filename:    "#{@profile_document.name}_oscal_profile_#{Date.today}.json",
              type:        JSON_CONTENT_TYPE,
              disposition: "attachment"
  # A document that fails schema validation must not 500 here. This is the
  # route the OSCAL export dropdown's JSON option actually points at, and
  # download_yaml / download_xml / download_oscal all degrade to a flash and
  # a bounce back — this one raised instead, purely because it was the one
  # sibling missing the rescue.
  rescue OscalValidationError => e
    Rails.logger.warn("OSCAL validation failed for Profile #{@profile_document.id}: #{e.message.to_s.truncate(300)}")
    flash[:warning] = SCHEMA_VALIDATION_FAILED_FLASH
    redirect_to profile_document_path(@profile_document, oscal_validation_failed: 1, oscal_format: "json")
  end

  def download_oscal_unvalidated
    service = OscalProfileExportService.new(@profile_document)
    oscal_data = service.export_unvalidated

    audit_log("profile_document_exported", subject: @profile_document, metadata: { name: @profile_document.name, format: "oscal_unvalidated" })
    send_data oscal_data,
              filename:    "#{@profile_document.name}_oscal_profile_unvalidated_#{Date.today}.json",
              type:        JSON_CONTENT_TYPE,
              disposition: "attachment"
  end

  def download_yaml
    service = OscalProfileExportService.new(@profile_document)
    json_string = params[:skip_validation] ? service.export_unvalidated : service.export
    yaml_data = OscalExportFormatService.to_yaml(json_string)

    audit_log("profile_document_exported", subject: @profile_document, metadata: { name: @profile_document.name, format: "yaml" })
    send_data yaml_data,
              filename:    "#{@profile_document.name}_oscal_profile_#{Date.today}.yaml",
              type:        "application/x-yaml",
              disposition: "attachment"
  rescue OscalValidationError => e
    Rails.logger.warn("OSCAL YAML validation failed for Profile #{@profile_document.id}: #{e.message.to_s.truncate(300)}")
    flash[:warning] = SCHEMA_VALIDATION_FAILED_FLASH
    redirect_to profile_document_path(@profile_document, oscal_validation_failed: 1, oscal_format: "yaml")
  end

  def download_xml
    service = OscalProfileExportService.new(@profile_document)
    json_string = params[:skip_validation] ? service.export_unvalidated : service.export
    xml_data = OscalExportFormatService.to_xml(json_string, :profile)

    audit_log("profile_document_exported", subject: @profile_document, metadata: { name: @profile_document.name, format: "xml" })
    send_data xml_data,
              filename:    "#{@profile_document.name}_oscal_profile_#{Date.today}.xml",
              type:        "application/xml",
              disposition: "attachment"
  rescue OscalValidationError => e
    Rails.logger.warn("OSCAL XML validation failed for Profile #{@profile_document.id}: #{e.message.to_s.truncate(300)}")
    flash[:warning] = SCHEMA_VALIDATION_FAILED_FLASH
    redirect_to profile_document_path(@profile_document, oscal_validation_failed: 1, oscal_format: "xml")
  end

  def update_metadata
    if @profile_document.update(document_metadata_params)
      @profile_document.regenerate_oscal_uuid!
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

  def download_resolved_catalog
    if @profile_document.resolved_catalog_json.blank?
      flash[:error] = "No resolved catalog available. Publish the profile first."
      redirect_to(profile_document_path(@profile_document)) && return
    end

    json_data = JSON.pretty_generate(@profile_document.resolved_catalog_json)
    audit_log("profile_document_exported", subject: @profile_document,
              metadata: { name: @profile_document.name, format: "resolved_catalog" })
    send_data json_data,
              filename:    "#{@profile_document.name}_resolved_catalog_#{Date.today}.json",
              type:        JSON_CONTENT_TYPE,
              disposition: "attachment"
  end

  def select_catalog
    @catalogs = ControlCatalog.order(:name)
  end

  def select_profile
    @profiles = ProfileDocument.where(lifecycle_status: "published")
                               .includes(:control_catalog)
                               .order(updated_at: :desc)
  end

  def create_from_profile
    source = ProfileDocument.find_by!(slug: params[:source_profile_id])

    unless source.published_lifecycle?
      flash[:error] = "Only published profiles can be used as a source."
      redirect_to(select_profile_profile_documents_path) && return
    end

    service = DocumentDuplicationService.new(source)
    copy = service.duplicate(
      new_name: params[:profile_name].presence || "Tailored from #{source.name}"
    )
    copy.update!(source_profile_id: source.id)

    audit_log("profile_document_created", subject: copy,
              metadata: { name: copy.name, creation_method: "from_profile", source_profile_id: source.id })
    flash[:success] = "Profile created from '#{source.name}' with #{copy.profile_controls.count} controls"
    redirect_to profile_document_path(copy)
  end

  def create_from_catalog
    catalog = ControlCatalog.find_for_url(params[:catalog_id]) || raise(ActiveRecord::RecordNotFound)
    control_ids = Array(params[:control_ids]).reject(&:blank?)

    if control_ids.empty?
      flash[:error] = "Please select at least one control"
      redirect_to(select_catalog_profile_documents_path) && return
    end

    profile = ProfileDocument.create!(
      name: params[:profile_name].presence || "Profile from #{catalog.name}",
      baseline_level: params[:baseline_level],
      control_catalog: catalog,
      status: "completed",
      lifecycle_status: "started",
      description: "Created from #{catalog.name} catalog"
    )

    catalog_controls = catalog.catalog_controls
                              .where(control_id: control_ids.flat_map { ControlId.forms(_1) })
                              .includes(:control_family)
    catalog_controls.each_with_index do |cc, idx|
      pc = profile.profile_controls.create!(
        control_id: cc.control_id,
        title: cc.title,
        control_family: cc.control_family&.code || cc.family_code,
        priority: ProfilePriorityAssignmentService.assign(cc),
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
      redirect_to(profile_document_path(@profile_document)) && return
    end

    @catalog = @profile_document.control_catalog
    @families = @catalog.control_families.includes(:catalog_controls).order(:sort_order, :code)
    # Both profile controls and catalog controls now use the same OSCAL canonical id format.
    @existing_control_ids = @profile_document.profile_controls.pluck(:control_id).to_set
  end

  def update_controls
    result = ProfileControlSelectionService.new(@profile_document).update(params[:control_ids])
    audit_log("profile_controls_bulk_updated", subject: @profile_document,
              metadata: { added: result.added, removed: result.removed })
    flash[:success] = "Controls updated: #{result.added} added, #{result.removed} removed"
    redirect_to profile_document_path(@profile_document)
  rescue ProfileControlSelectionService::SelectionError => e
    flash[:error] = e.message
    redirect_to profile_document_path(@profile_document)
  end

  def status
    render json: {
      status: @profile_document.status,
      error_message: @profile_document.error_message
    }
  end

  # Override publish_check to include Profile-specific prioritization check.
  # Resolved profiles (externally sourced) skip prioritization and parameter checks.
  def publish_check
    service = PublicationValidationService.new(@profile_document, current_user: current_user)
    readiness = service.publication_readiness

    unless resolved_profile?
      # Add prioritization check for user-created profiles
      unprioritized = @profile_document.profile_controls.where(priority: [ nil, "" ]).count
      prioritized = unprioritized == 0
      readiness[:checks][:controls_prioritized] = prioritized

      unless prioritized
        readiness[:ready] = false
        readiness[:errors] << "#{unprioritized} control#{'s' if unprioritized != 1} missing prioritization (P1/P2/P3)"
      end

      # Add parameter completeness check
      uncustomized = count_uncustomized_parameters(@profile_document)
      readiness[:checks][:parameters_customized] = uncustomized == 0

      unless uncustomized == 0
        readiness[:ready] = false
        readiness[:errors] << "#{uncustomized} parameter#{'s' if uncustomized != 1} still have default catalog values"
      end
    end

    render json: readiness
  end

  private

  def publish_config
    { document: @profile_document, audit_event: "profile_document_published",
      redirect_path: profile_document_path(@profile_document), label: "Profile" }
  end

  # Profile-specific pre-publish logic: validate catalog link, prioritization, and generate resolved catalog.
  # Resolved profiles already have resolved_catalog_json populated from import — skip regeneration.
  def before_publish_lifecycle(doc)
    is_resolved = doc.import_metadata&.dig("format") == "oscal_resolved_profile"

    unless is_resolved
      unless doc.control_catalog
        return { error: "Cannot publish: no source catalog linked to this profile." }
      end

      unprioritized = doc.profile_controls.where(priority: [ nil, "" ]).count
      if unprioritized > 0
        return { error: "Cannot publish: #{unprioritized} control#{'s' if unprioritized != 1} missing prioritization (P1/P2/P3). Assign priorities before publishing." }
      end

      service = OscalResolvedProfileCatalogService.new(doc)
      resolved_json = service.export
      doc.update!(resolved_catalog_json: JSON.parse(resolved_json))
    end

    nil
  end

  # Check if the current profile is a resolved profile (externally sourced).
  def resolved_profile?
    @profile_document.import_metadata&.dig("format") == "oscal_resolved_profile"
  end

  # Count parameters where the value still matches the catalog label (unchanged).
  def count_uncustomized_parameters(profile)
    param_fields = ProfileControlField.joins(:profile_control)
      .where(profile_controls: { profile_document_id: profile.id })
      .where("profile_control_fields.field_name LIKE 'parameter:%'")
      .where("profile_control_fields.field_name NOT LIKE 'parameter_label:%'")

    count = 0
    param_fields.find_each do |field|
      label_field = ProfileControlField.find_by(
        profile_control_id: field.profile_control_id,
        field_name: field.field_name.sub("parameter:", "parameter_label:")
      )
      count += 1 if label_field && field.field_value == label_field.field_value
    end
    count
  end

  def document_metadata_params
    permitted = params.require(:profile_document).permit(:name, :profile_version, :oscal_version, :description, :published)
    merge_metadata_extra(permitted, :profile_document)
  end

  # #919 — mirrors the Api::V1 sibling exactly so the two surfaces cannot
  # drift. authorize_permission! carries the admin bypass, honours
  # SparcConfig.any_auth_enabled?, and emits the authorization_failure audit
  # event; a hand-rolled check loses all three.
  def authorize_profiles_write!
    authorize_permission!("profiles.write")
  end

  def set_profile_document
    @profile_document = ProfileDocument.find_by!(slug: params[:id])
  end

  # OscalExportable hooks
  def oscal_export_document = @profile_document
  def oscal_export_service(doc) = OscalProfileExportService.new(doc)
  def oscal_document_type_label = "Profile"

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
