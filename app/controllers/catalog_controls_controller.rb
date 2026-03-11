class CatalogControlsController < ApplicationController
  before_action :set_control_family, only: [ :new, :create, :batch_new, :batch_create ]
  before_action :set_catalog_control, only: [ :edit, :update, :destroy ]
  before_action :authorize_catalog_write!

  def new
    @catalog_control = @control_family.catalog_controls.new
  end

  def create
    permitted = catalog_control_params
    @catalog_control = @control_family.catalog_controls.new(permitted.except(:params_labels))
    apply_params_labels!(permitted)
    if @catalog_control.save
      audit_log("catalog_control_created", subject: @catalog_control, metadata: { control_id: @catalog_control.control_id })
      redirect_to @control_family, notice: "Control '#{@catalog_control.control_id}' was added."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @control_family = @catalog_control.control_family
  end

  def update
    permitted = catalog_control_params
    apply_params_labels!(permitted)
    if @catalog_control.update(permitted.except(:params_labels))
      audit_log("catalog_control_updated", subject: @catalog_control, metadata: { control_id: @catalog_control.control_id })
      redirect_to @catalog_control.control_family, notice: "Control updated successfully."
    else
      @control_family = @catalog_control.control_family
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    family = @catalog_control.control_family
    audit_log("catalog_control_deleted", subject: @catalog_control, metadata: { control_id: @catalog_control.control_id })
    @catalog_control.destroy
    redirect_to family, notice: "Control was deleted."
  end

  def batch_new
    @control_catalog = @control_family.control_catalog
  end

  def batch_create
    controls_text = params[:controls_text].to_s.strip
    if controls_text.blank?
      @control_catalog = @control_family.control_catalog
      flash.now[:error] = "Please enter at least one control."
      return render :batch_new, status: :unprocessable_entity
    end

    created = 0
    errors = []

    ActiveRecord::Base.transaction do
      controls_text.each_line do |line|
        line = line.strip
        next if line.blank?

        control_id, title = line.split(/\s*[|,]\s*/, 2)
        control_id = control_id.to_s.strip
        title = title.to_s.strip.presence

        next if control_id.blank?

        control = @control_family.catalog_controls.build(control_id: control_id, title: title)
        if control.save
          created += 1
        else
          errors << "#{control_id}: #{control.errors.full_messages.join(', ')}"
        end
      end
    end

    if errors.any?
      @control_catalog = @control_family.control_catalog
      flash.now[:error] = "#{created} controls added. Errors: #{errors.join('; ')}"
      render :batch_new, status: :unprocessable_entity
    else
      audit_log("catalog_control_created", subject: @control_family, metadata: { count: created, family_id: @control_family.id })
      redirect_to @control_family, notice: "#{created} #{'control'.pluralize(created)} added successfully."
    end
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
      guidance_data: {},
      params_labels: {}
    )
  end

  # Extracts params_labels from the permitted params hash and merges
  # the updated labels back into @catalog_control.params_data.
  def apply_params_labels!(permitted)
    labels = permitted[:params_labels]
    return if labels.blank?

    @catalog_control.params_data = @catalog_control.merge_params_labels(labels.to_h)
  end

  def authorize_catalog_write!
    authorize_permission!("catalogs.write")
  end
end
