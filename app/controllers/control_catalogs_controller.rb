class ControlCatalogsController < ApplicationController
  before_action :set_control_catalog, only: [
    :show, :edit, :update, :destroy, :update_metadata,
    :download_oscal, :download_oscal_validated, :download_oscal_unvalidated
  ]

  def index
    @control_catalogs = ControlCatalog.includes(:control_families).order(:name)
  end

  def show
    @control_families = @control_catalog.control_families.includes(:catalog_controls)
  end

  def new
    @control_catalog = ControlCatalog.new
  end

  def create
    @control_catalog = ControlCatalog.new(control_catalog_params)
    if @control_catalog.save
      redirect_to @control_catalog, notice: "Catalog '#{@control_catalog.name}' was created successfully."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @control_catalog.update(control_catalog_params)
      redirect_to @control_catalog, notice: "Catalog updated successfully."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    name = @control_catalog.name
    @control_catalog.destroy
    redirect_to control_catalogs_path, notice: "Catalog '#{name}' was deleted."
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

    begin
      stats = CatalogImportService.call(file, file.original_filename)
      flash[:success] = "Imported \u201c#{stats[:catalog].name}\u201d: " \
                        "#{stats[:families]} families, #{stats[:controls]} controls " \
                        "(#{stats[:created]} created, #{stats[:updated]} updated)."
      redirect_to stats[:catalog]
    rescue CatalogImportService::ImportError => e
      flash.now[:error] = e.message
      render :import, status: :unprocessable_entity
    rescue StandardError => e
      flash.now[:error] = "Import failed: #{e.message}"
      render :import, status: :unprocessable_entity
    end
  end

  def update_metadata
    if @control_catalog.update(catalog_metadata_params)
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
      download_url = download_oscal_validated_control_catalog_path(@control_catalog)
      flash[:success] = "OSCAL export passed schema validation (v#{result.schema_version}). " \
                        "<a href=\"#{download_url}\">Download OSCAL file</a>.".html_safe
    else
      Rails.logger.warn("OSCAL validation failed for Catalog #{@control_catalog.id}: #{result.errors.first(3).join('; ')}")
      download_url = download_oscal_unvalidated_control_catalog_path(@control_catalog)
      flash[:warning] = "OSCAL export failed schema validation. " \
                        "<a href=\"#{download_url}\">Download unvalidated version</a>.".html_safe
    end

    redirect_to control_catalog_path(@control_catalog)
  end

  def download_oscal_validated
    service = OscalCatalogExportService.new(@control_catalog)
    oscal_data = service.export

    send_data oscal_data,
              filename:    "#{@control_catalog.name}_oscal_catalog_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
  end

  def download_oscal_unvalidated
    service = OscalCatalogExportService.new(@control_catalog)
    oscal_data = service.export_unvalidated

    send_data oscal_data,
              filename:    "#{@control_catalog.name}_oscal_catalog_unvalidated_#{Date.today}.json",
              type:        "application/json",
              disposition: "attachment"
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
end
