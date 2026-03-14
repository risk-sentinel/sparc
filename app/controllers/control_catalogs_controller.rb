class ControlCatalogsController < ApplicationController
  skip_before_action :require_authentication, only: [ :index, :show, :baseline_controls ]

  before_action :set_control_catalog, only: [
    :show, :edit, :update, :destroy, :update_metadata,
    :download_oscal, :download_oscal_validated, :download_oscal_unvalidated,
    :download_yaml, :download_xml, :baseline_controls
  ]
  before_action :authorize_catalog_write!, only: [
    :new, :create, :edit, :update, :destroy, :import, :update_metadata
  ]

  def index
    @control_catalogs = ControlCatalog.includes(:control_families).order(:name)
    @total_count = @control_catalogs.size
    @family_count = ControlFamily.count
    @control_count = CatalogControl.count
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

    # Create a pending catalog record and stash the file for background processing
    catalog = ControlCatalog.create!(
      name: File.basename(original_filename, ".*").tr("_", " "),
      status: "pending",
      original_filename: original_filename
    )

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
    json_string = OscalCatalogExportService.new(@control_catalog).export
    yaml_data = OscalExportFormatService.to_yaml(json_string)

    audit_log("control_catalog_exported", subject: @control_catalog, metadata: { name: @control_catalog.name, format: "yaml" })
    send_data yaml_data,
              filename:    "#{@control_catalog.name}_oscal_catalog_#{Date.today}.yaml",
              type:        "application/x-yaml",
              disposition: "attachment"
  end

  def download_xml
    json_string = OscalCatalogExportService.new(@control_catalog).export
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
  def baseline_controls
    level = params[:level].to_s.strip.downcase
    control_ids = if level.present?
      @control_catalog.catalog_controls
                      .where("LOWER(baseline_impact) LIKE ?", "%#{level}%")
                      .pluck(:control_id)
    else
      []
    end
    render json: { control_ids: control_ids }
  end

  private

  def set_control_catalog
    @control_catalog = ControlCatalog.find(params[:id])
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
end
