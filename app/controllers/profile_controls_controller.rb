class ProfileControlsController < ApplicationController
  before_action :set_profile_document
  before_action :set_profile_control, only: %i[edit update destroy]

  def new
    @profile_control = @profile_document.profile_controls.build
  end

  def create
    @profile_control = @profile_document.profile_controls.build(profile_control_params)
    @profile_control.row_order = (@profile_document.profile_controls.maximum(:row_order) || 0) + 1

    if @profile_control.save
      save_editable_fields
      audit_log("profile_control_created", subject: @profile_control, metadata: { control_id: @profile_control.control_id, profile_document_id: @profile_document.id })
      flash[:success] = "Control #{@profile_control.control_id} added to profile"
      redirect_to profile_document_path(@profile_document)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @profile_control.update(profile_control_params)
      save_editable_fields
      audit_log("profile_control_updated", subject: @profile_control, metadata: { control_id: @profile_control.control_id })
      flash[:success] = "Control #{@profile_control.control_id} updated"
      redirect_to profile_document_path(@profile_document)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    control_id = @profile_control.control_id
    audit_log("profile_control_deleted", subject: @profile_control, metadata: { control_id: control_id })
    @profile_control.destroy
    flash[:success] = "Control #{control_id} removed from profile"
    redirect_to profile_document_path(@profile_document)
  end

  private

  def set_profile_document
    @profile_document = ProfileDocument.find(params[:profile_document_id])
  end

  def set_profile_control
    @profile_control = @profile_document.profile_controls.find(params[:id])
  end

  def profile_control_params
    params.require(:profile_control).permit(:control_id, :title, :priority)
  end

  def save_editable_fields
    (params[:fields] || {}).each do |field_name, value|
      next unless ProfileControlField::EDITABLE_FIELDS.include?(field_name.to_s)

      field = @profile_control.profile_control_fields.find_or_initialize_by(field_name: field_name.to_s)
      field.field_value = value.to_s.strip
      field.save!
    end
  end
end
