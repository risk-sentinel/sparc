# Admin UI for OSCAL POA&M risks (#423).
#
# Risks are the canonical risk-management artifact inside a POA&M.
# Items reference one or more risks via PoamItemRisk; Items + Findings +
# Observations all link back to risks through their respective join
# models.
#
# This controller provides full CRUD scoped under the parent POAM
# document. UUIDs are generated server-side; manual editing of the UUID
# is not exposed through the form (round-trip with the OSCAL parser
# preserves imported UUIDs).
class PoamRisksController < ApplicationController
  include OscalExtensibilityParams

  before_action :set_poam_document
  before_action :set_poam_risk, only: %i[edit update destroy]

  def new
    @poam_risk = @poam_document.poam_risks.build
  end

  def create
    @poam_risk = @poam_document.poam_risks.build(poam_risk_params)
    @poam_risk.uuid ||= SecureRandom.uuid

    if @poam_risk.save
      audit_log("poam_risk_created", subject: @poam_risk,
                metadata: { title: @poam_risk.title, poam_document_id: @poam_document.id })
      flash[:success] = "Risk added"
      redirect_to poam_document_path(@poam_document)
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @poam_risk.update(poam_risk_params)
      audit_log("poam_risk_updated", subject: @poam_risk,
                metadata: { title: @poam_risk.title })
      flash[:success] = "Risk updated"
      redirect_to poam_document_path(@poam_document)
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @poam_risk.title
    audit_log("poam_risk_deleted", subject: @poam_risk, metadata: { title: title })
    @poam_risk.destroy
    flash[:success] = "Risk \"#{title}\" removed"
    redirect_to poam_document_path(@poam_document)
  end

  private

  def set_poam_document
    @poam_document = PoamDocument.find_by!(slug: params[:poam_document_id])
  end

  def set_poam_risk
    @poam_risk = @poam_document.poam_risks.find(params[:id])
  end

  def poam_risk_params
    permitted = params.require(:poam_risk).permit(
      :title, :description, :statement, :status,
      :impact, :likelihood, :deadline, :remarks,
      props_data:   [ :name, :value, :class, :ns, :uuid, :remarks ],
      links_data:   [ :href, :rel, :media_type, :text ],
      origins_data: [ :actor_type, :actor_uuid, :role_id ]
    )

    permitted[:props_data]   = compact_props(permitted[:props_data])     if permitted.key?(:props_data)
    permitted[:links_data]   = compact_links(permitted[:links_data])     if permitted.key?(:links_data)
    permitted[:origins_data] = compact_origins(permitted[:origins_data]) if permitted.key?(:origins_data)
    permitted
  end
end
