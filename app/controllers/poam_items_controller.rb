class PoamItemsController < ApplicationController
  before_action :set_poam_document
  before_action :set_poam_item, only: %i[edit update destroy]

  def new
    @poam_item = @poam_document.poam_items.build
    load_association_options
  end

  def create
    @poam_item = @poam_document.poam_items.build(poam_item_params)
    @poam_item.row_order = (@poam_document.poam_items.maximum(:row_order) || 0) + 1
    @poam_item.poam_item_uuid = SecureRandom.uuid

    if @poam_item.save
      sync_associations
      audit_log("poam_item_created", subject: @poam_item, metadata: { title: @poam_item.title, poam_document_id: @poam_document.id })
      flash[:success] = "POA&M item added"
      redirect_to poam_document_path(@poam_document)
    else
      load_association_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_association_options
  end

  def update
    if @poam_item.update(poam_item_params)
      sync_associations
      audit_log("poam_item_updated", subject: @poam_item, metadata: { title: @poam_item.title })
      flash[:success] = "POA&M item updated"
      redirect_to poam_document_path(@poam_document)
    else
      load_association_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @poam_item.title
    audit_log("poam_item_deleted", subject: @poam_item, metadata: { title: title })
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
    params.require(:poam_item).permit(
      :title, :description, :risk_status, :risk_level,
      :likelihood, :impact, :deadline,
      :internal_notes, :closure_evidence, :remarks
    )
  end

  def load_association_options
    @available_risks        = @poam_document.poam_risks.order(:title)
    @available_observations = @poam_document.poam_observations.order(:title)
    @available_findings     = @poam_document.poam_findings.order(:title)
  end

  def sync_associations
    if params[:poam_risk_ids].present?
      @poam_item.poam_risk_ids = params[:poam_risk_ids].reject(&:blank?).map(&:to_i)
    end

    if params[:poam_observation_ids].present?
      @poam_item.poam_observation_ids = params[:poam_observation_ids].reject(&:blank?).map(&:to_i)
    end

    if params[:poam_finding_ids].present?
      @poam_item.poam_finding_ids = params[:poam_finding_ids].reject(&:blank?).map(&:to_i)
    end
  end
end
