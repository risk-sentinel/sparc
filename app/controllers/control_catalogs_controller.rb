class ControlCatalogsController < ApplicationController
  before_action :set_control_catalog, only: [:show, :edit, :update, :destroy]

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

  private

  def set_control_catalog
    @control_catalog = ControlCatalog.find(params[:id])
  end

  def control_catalog_params
    params.require(:control_catalog).permit(:name, :version, :description, :source)
  end
end
