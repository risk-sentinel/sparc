# frozen_string_literal: true

class ControlMappingEntriesController < ApplicationController
  before_action :authorize_mapping_write!
  before_action :set_control_mapping

  def create
    @entry = @control_mapping.control_mapping_entries.new(entry_params)

    if @entry.save
      redirect_to @control_mapping, flash: { success: "Mapping entry added." }
    else
      redirect_to @control_mapping, flash: { error: "Failed to add entry: #{@entry.errors.full_messages.join(', ')}" }
    end
  end

  def destroy
    entry = @control_mapping.control_mapping_entries.find(params[:id])
    entry.destroy
    redirect_to @control_mapping, flash: { success: "Mapping entry removed." }
  end

  private

  def set_control_mapping
    @control_mapping = ControlMapping.find(params[:control_mapping_id])
  end

  def entry_params
    params.require(:control_mapping_entry).permit(
      :source_control_id, :source_type,
      :target_control_id, :target_type,
      :relationship, :matching_rationale, :remarks
    )
  end

  def authorize_mapping_write!
    authorize_permission!("mappings.write")
  end
end
