class ControlCatalogsController < ApplicationController
  include Publishable
  include OscalExportable
  skip_before_action :require_authentication, only: [ :index, :show, :baseline_controls ]

  before_action :set_control_catalog, only: [
    :show, :edit, :update, :destroy, :update_metadata,
    :download_oscal, :download_oscal_validated, :download_oscal_unvalidated,
    :download_yaml, :download_xml, :validate_oscal_export, :baseline_controls,
    :update_baseline, :bulk_update_baselines,
    :publish, :publish_check, :acknowledge_warnings
  ]
  before_action :ensure_editable!, only: [ :update, :update_baseline, :bulk_update_baselines, :publish ]
  before_action :authorize_catalog_write!, only: [
    :new, :create, :edit, :update, :destroy, :import, :update_metadata,
    :update_baseline, :bulk_update_baselines, :publish
  ]

  def index
    @control_catalogs = ControlCatalog.includes(:control_families).order(:name)
    @total_count = @control_catalogs.size
    @family_count = ControlFamily.distinct.count(:code)
    @control_count = CatalogControl.distinct.count(:control_id)
    @revision_count = ControlCatalog.where.not(version: [ nil, "" ]).select(:version).distinct.count
  end

  def show
    @control_families = @control_catalog.control_families.includes(:catalog_controls)

    respond_to do |format|
      format.html
      format.json do
        render json: {
          id: @control_catalog.id,
          name: @control_catalog.name,
          control_families: @control_families.map do |family|
            {
              code: family.code,
              name: family.name,
              catalog_controls: family.catalog_controls.map do |ctrl|
                { control_id: ctrl.control_id, title: ctrl.title }
              end
            }
          end
        }
      end
    end
  end

  def new
    @control_catalog = ControlCatalog.new
  end

  def create
    template = params.dig(:control_catalog, :template) || "blank"

    begin
      @control_catalog = CatalogBuilderService.new(
        name: control_catalog_params[:name],
        template: template,
        version: control_catalog_params[:version],
        source: control_catalog_params[:source],
        description: control_catalog_params[:description]
      ).build

      audit_log("control_catalog_created", subject: @control_catalog, metadata: { name: @control_catalog.name })
      redirect_to @control_catalog, notice: "Catalog '#{@control_catalog.name}' was created successfully."
    rescue ActiveRecord::RecordInvalid => e
      @control_catalog = ControlCatalog.new(control_catalog_params)
      @control_catalog.valid?
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @control_catalog.update(control_catalog_params)
      audit_log("control_catalog_updated", subject: @control_catalog, metadata: { name: @control_catalog.name })
      redirect_to @control_catalog, notice: "Catalog updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @control_catalog.name
    if @control_catalog.destroy
      audit_log("control_catalog_deleted", subject: @control_catalog, metadata: { name: name })
      redirect_to control_catalogs_path, notice: "Catalog '#{name}' was deleted."
    else
      audit_log("control_catalog_delete_blocked", subject: @control_catalog,
        metadata: { name: name, reason: @control_catalog.errors.full_messages.join(", ") })
      flash[:error] = @control_catalog.errors.full_messages.join(", ")
      redirect_to control_catalog_path(@control_catalog)
    end
  end

  # PATCH /control_catalogs/:id/acknowledge_warnings
  # Marks import warnings as acknowledged so the modal doesn't re-appear.
  def acknowledge_warnings
    @control_catalog.update!(
      metadata_extra: (@control_catalog.metadata_extra || {}).merge(
        "import_warnings_acknowledged" => true
      )
    )
    render json: { acknowledged: true }
  end

  # GET  /control_catalogs/import
  # POST /control_catalogs/import
  def import
    return unless request.post?

    file = params[:catalog_file]
    unless file.present?
      flash.now[:error] = "Please select a file to import."
      return render :import, status: :unprocessable_entity
    end

    original_filename = file.original_filename
    sanitized_filename = File.basename(original_filename)

    # Check for existing catalog to avoid duplicates.
    # Try original_filename first (most reliable for re-imports), then inferred name.
    inferred_name = File.basename(original_filename, ".*").tr("_", " ")
    catalog = ControlCatalog.find_by(original_filename: original_filename) ||
              ControlCatalog.find_by(name: inferred_name)

    if catalog
      # Reset for re-import — clear any previous warnings acknowledgement
      catalog.update!(
        status: "pending",
        error_message: nil,
        original_filename: original_filename,
        metadata_extra: (catalog.metadata_extra || {}).except(
          "import_warnings", "import_warnings_summary", "import_warnings_acknowledged"
        )
      )
    else
      catalog = ControlCatalog.create!(
        name: inferred_name,
        status: "pending",
        original_filename: original_filename
      )
    end

    # Copy uploaded file to a temp path that persists past the request
    tmp_path = Rails.root.join("tmp", "catalog_import_#{catalog.id}_#{sanitized_filename}")
    FileUtils.cp(file.tempfile.path, tmp_path)

    CatalogImportJob.perform_later(catalog.id, tmp_path.to_s, original_filename)
    audit_log("control_catalog_imported", subject: catalog, metadata: { name: catalog.name })
    redirect_to catalog
  end

  def update_metadata
    if @control_catalog.update(catalog_metadata_params)
      audit_log("control_catalog_updated", subject: @control_catalog, metadata: { name: @control_catalog.name, metadata_update: true })
      flash[:success] = "Catalog metadata updated"
    else
      flash[:error] = @control_catalog.errors.full_messages.join(", ")
    end
    redirect_to control_catalog_path(@control_catalog)
  end

  def download_oscal
    service = OscalCatalogExportService.new(@control_catalog)
    result = service.validation_result

    if result.valid?
      audit_log("control_catalog_exported", subject: @control_catalog, metadata: { name: @control_catalog.name, format: "oscal" })
      send_data service.export,
                filename:    "#{@control_catalog.name}_oscal_catalog_#{Date.today}.json",
                type:        "application/json",
                disposition: "attachment"
    else
      Rails.logger.warn("OSCAL validation failed for Catalog #{@control_catalog.id}: #{result.errors.first(3).join('; ')}")
      flash[:warning] = "OSCAL export failed schema validation. Use the unvalidated download instead."
      redirect_to control_catalog_path(@control_catalog)
    end
  end

  def download_oscal_validated
    service = OscalCatalogExportService.new(@control_catalog)
    oscal_data = service.export

    audit_log("control_catalog_exported", subject: @control_catalog, metadata: { name: @control_catalog.name, format: "oscal" })
    send_data oscal_data,
              filename:    "#{@control_catalog.name}_oscal_catalog_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_oscal_unvalidated
    service = OscalCatalogExportService.new(@control_catalog)
    oscal_data = service.export_unvalidated

    audit_log("control_catalog_exported", subject: @control_catalog, metadata: { name: @control_catalog.name, format: "oscal" })
    send_data oscal_data,
              filename:    "#{@control_catalog.name}_oscal_catalog_unvalidated_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_yaml
    service = OscalCatalogExportService.new(@control_catalog)
    json_string = params[:skip_validation] ? service.export_unvalidated : service.export
    yaml_data = OscalExportFormatService.to_yaml(json_string)

    audit_log("control_catalog_exported", subject: @control_catalog, metadata: { name: @control_catalog.name, format: "yaml" })
    send_data yaml_data,
              filename:    "#{@control_catalog.name}_oscal_catalog_#{Date.today}.yaml",
              type:        "application/x-yaml",
              disposition: "attachment"
  end

  def download_xml
    service = OscalCatalogExportService.new(@control_catalog)
    json_string = params[:skip_validation] ? service.export_unvalidated : service.export
    xml_data = OscalExportFormatService.to_xml(json_string, :catalog)

    audit_log("control_catalog_exported", subject: @control_catalog, metadata: { name: @control_catalog.name, format: "xml" })
    send_data xml_data,
              filename:    "#{@control_catalog.name}_oscal_catalog_#{Date.today}.xml",
              type:        "application/xml",
              disposition: "attachment"
  end

  # Returns control IDs matching a given baseline level.
  # Used by the family-selector Stimulus controller for baseline auto-select.
  # GET /control_catalogs/:id/baseline_controls.json?level=MODERATE
  # Matches both full names ("LOW", "MODERATE", "HIGH") and abbreviated
  # formats ("L", "M", "H") stored in baseline_impact.
  def baseline_controls
    level = params[:level].to_s.strip.upcase
    abbrev = { "LOW" => "L", "MODERATE" => "M", "HIGH" => "H" }[level]

    control_ids = if level.present?
      scope = @control_catalog.catalog_controls
      if abbrev
        # Match either the full name or the abbreviation (case-insensitive)
        scope.where(
          "LOWER(baseline_impact) LIKE :full OR baseline_impact LIKE :abbrev_word",
          full: "%#{level.downcase}%",
          abbrev_word: "%#{abbrev}%"
        ).pluck(:control_id)
      else
        scope.where("LOWER(baseline_impact) LIKE ?", "%#{level.downcase}%").pluck(:control_id)
      end
    else
      []
    end
    render json: { control_ids: control_ids }
  end

  # PATCH /control_catalogs/:id/update_baseline
  # Updates baseline_impact on a single catalog control (inline edit).
  def update_baseline
    control = @control_catalog.catalog_controls.find(params[:control_id])
    control.update!(baseline_impact: params[:baseline_impact].presence)

    audit_log("catalog_control_baseline_updated", subject: @control_catalog,
      metadata: { control_id: control.control_id, baseline_impact: control.baseline_impact })
    render json: { success: true, baseline_impact: control.baseline_impact }
  rescue ActiveRecord::RecordNotFound
    render json: { success: false, error: "Control not found" }, status: :not_found
  end

  # PATCH /control_catalogs/:id/bulk_update_baselines
  # Bulk-updates baseline_impact on multiple catalog controls.
  # Params: control_ids[], baseline_level (LOW/MODERATE/HIGH), action (add/remove/set)
  def bulk_update_baselines
    control_ids = Array(params[:control_ids]).map(&:to_i).reject(&:zero?)
    level = params[:baseline_level].to_s.strip.upcase
    bulk_action = params[:action_type].to_s.strip

    if control_ids.empty?
      render json: { success: false, error: "No controls selected" }, status: :unprocessable_entity
      return
    end

    controls = @control_catalog.catalog_controls.where(id: control_ids)
    updated = 0

    ActiveRecord::Base.transaction do
      controls.find_each do |control|
        case bulk_action
        when "add"
          control.add_baseline_level(level)
        when "remove"
          control.remove_baseline_level(level)
        when "set"
          control.baseline_impact = level.present? ? level : nil
        else
          raise ArgumentError, "Invalid action: #{bulk_action}"
        end
        control.save!
        updated += 1
      end
    end

    audit_log("catalog_control_baselines_bulk_updated", subject: @control_catalog,
      metadata: { action: bulk_action, level: level, updated_count: updated })
    render json: { success: true, updated_count: updated }
  rescue ArgumentError => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
  end

  private

  def publish_config
    { document: @control_catalog, audit_event: "control_catalog_published",
      redirect_path: control_catalog_path(@control_catalog), label: "Catalog" }
  end

  def set_control_catalog
    @control_catalog = ControlCatalog.find_by!(slug: params[:id])
  end

  def ensure_editable!
    return unless @control_catalog.published_lifecycle?

    flash[:error] = "This catalog is published and read-only. Create a copy to make changes."
    redirect_to control_catalog_path(@control_catalog)
  end

  def control_catalog_params
    params.require(:control_catalog).permit(:name, :version, :description, :source)
  end

  def catalog_metadata_params
    permitted = params.require(:control_catalog).permit(:name, :version, :oscal_version, :description, :published)
    merge_metadata_extra(permitted, :control_catalog)
  end

  def authorize_catalog_write!
    authorize_permission!("catalogs.write")
  end

  # OscalExportable hooks
  def oscal_export_document = @control_catalog
  def oscal_export_service(doc) = OscalCatalogExportService.new(doc)
  def oscal_document_type_label = "Catalog"
end
