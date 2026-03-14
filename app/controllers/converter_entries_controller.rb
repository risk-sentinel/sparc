# frozen_string_literal: true

class ConverterEntriesController < ApplicationController
  before_action :authorize_converter_write!
  before_action :set_converter

  def create
    @entry = @converter.converter_entries.new(entry_params)

    if @entry.save
      audit_log("converter_entry_created", subject: @entry, metadata: { converter_id: @converter.id, source_id: @entry.source_id, target_id: @entry.target_id })
      redirect_to @converter, flash: { success: "Converter entry added." }
    else
      redirect_to @converter, flash: { error: "Failed to add entry: #{@entry.errors.full_messages.join(', ')}" }
    end
  end

  def destroy
    entry = @converter.converter_entries.find(params[:id])
    audit_log("converter_entry_deleted", subject: entry, metadata: { converter_id: @converter.id })
    entry.destroy
    redirect_to @converter, flash: { success: "Converter entry removed." }
  end

  private

  def set_converter
    @converter = Converter.find(params[:converter_id])
  end

  def entry_params
    params.require(:converter_entry).permit(
      :source_id, :target_id, :relationship, :category, :remarks
    )
  end

  def authorize_converter_write!
    authorize_permission!("converters.write")
  end
end
