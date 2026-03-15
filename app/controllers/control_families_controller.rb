class ControlFamiliesController < ApplicationController
  skip_before_action :require_authentication, only: [ :show ]

  before_action :set_control_catalog, only: [ :new, :create ]
  before_action :set_control_family, only: [ :show, :edit, :update, :destroy ]
  before_action :authorize_catalog_write!, only: [ :new, :create, :edit, :update, :destroy ]

  def show
    @catalog_controls = @control_family.catalog_controls.order(:control_id)
    @control_catalog = @control_family.control_catalog
  end

  def new
    @control_family = @control_catalog.control_families.new
  end

  def create
    @control_family = @control_catalog.control_families.new(control_family_params)
    if @control_family.save
      audit_log("control_family_created", subject: @control_family, metadata: { code: @control_family.code, name: @control_family.name })
      redirect_to @control_family, notice: "Family '#{@control_family.code} - #{@control_family.name}' was created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @control_catalog = @control_family.control_catalog
  end

  def update
    if @control_family.update(control_family_params)
      audit_log("control_family_updated", subject: @control_family, metadata: { code: @control_family.code, name: @control_family.name })
      redirect_to @control_family, notice: "Family updated successfully."
    else
      @control_catalog = @control_family.control_catalog
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    catalog = @control_family.control_catalog
    code = @control_family.code
    name = @control_family.name
    audit_log("control_family_deleted", subject: @control_family, metadata: { code: code, name: name })
    @control_family.destroy
    redirect_to catalog, notice: "Family was deleted."
  end

  private

  def set_control_catalog
    @control_catalog = ControlCatalog.find_by!(slug: params[:control_catalog_id])
  end

  def set_control_family
    @control_family = ControlFamily.find(params[:id])
  end

  def control_family_params
    params.require(:control_family).permit(:code, :name, :description, :sort_order)
  end

  def authorize_catalog_write!
    authorize_permission!("catalogs.write")
  end
end
