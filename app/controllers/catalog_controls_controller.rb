class CatalogControlsController < ApplicationController
  before_action :set_control_family, only: [ :new, :create ]
  before_action :set_catalog_control, only: [ :edit, :update, :destroy ]

  def new
    @catalog_control = @control_family.catalog_controls.new
  end

  def create
    @catalog_control = @control_family.catalog_controls.new(catalog_control_params)
    if @catalog_control.save
      redirect_to @control_family, notice: "Control '#{@catalog_control.control_id}' was added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @control_family = @catalog_control.control_family
  end

  def update
    if @catalog_control.update(catalog_control_params)
      redirect_to @catalog_control.control_family, notice: "Control updated successfully."
    else
      @control_family = @catalog_control.control_family
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    family = @catalog_control.control_family
    @catalog_control.destroy
    redirect_to family, notice: "Control was deleted."
  end

  private

  def set_control_family
    @control_family = ControlFamily.find(params[:control_family_id])
  end

  def set_catalog_control
    @catalog_control = CatalogControl.find(params[:id])
  end

  def catalog_control_params
    params.require(:catalog_control).permit(
      :control_id, :title, :description, :priority, :baseline_impact,
      guidance_data: {}
    )
  end
end
