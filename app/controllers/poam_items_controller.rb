class PoamItemsController < ApplicationController
  before_action :set_poam_document
  before_action :set_poam_item, only: %i[edit update destroy]

  def new
    @poam_item = @poam_document.poam_items.build
  end

  def create
    @poam_item = @poam_document.poam_items.build(poam_item_params)
    @poam_item.row_order = (@poam_document.poam_items.maximum(:row_order) || 0) + 1
    @poam_item.poam_item_uuid = SecureRandom.uuid

    if @poam_item.save
      save_editable_fields
      flash[:success] = "POA&M item added"
      redirect_to poam_document_path(@poam_document)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @poam_item.update(poam_item_params)
      save_editable_fields
      flash[:success] = "POA&M item updated"
      redirect_to poam_document_path(@poam_document)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @poam_item.title
    @poam_item.destroy
    flash[:success] = "POA&M item \"#{title}\" removed"
    redirect_to poam_document_path(@poam_document)
  end

  private

  def set_poam_document
    @poam_document = PoamDocument.find(params[:poam_document_id])
  end

  def set_poam_item
    @poam_item = @poam_document.poam_items.find(params[:id])
  end

  def poam_item_params
    params.require(:poam_item).permit(:title, :description, :risk_status, :risk_level, :likelihood, :impact, :deadline)
  end

  def save_editable_fields
    (params[:fields] || {}).each do |field_name, value|
      next unless PoamItemField::EDITABLE_FIELDS.include?(field_name.to_s)
      field = @poam_item.poam_item_fields.find_or_initialize_by(field_name: field_name.to_s)
      field.field_value = value.to_s.strip
      field.save!
    end
  end
end
