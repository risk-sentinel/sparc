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
  include RiskCollectionParams

  before_action :set_poam_document
  include PoamChildAuthorization
  # #919 — every action here is authoring (new/create/edit/update/destroy), so all
  # of them require poam.write on the parent document's boundary. Runs AFTER
  # set_poam_document, which is what resolves that boundary.
  before_action :authorize_poam_write!
  before_action :set_poam_risk, only: %i[edit update destroy]

  def new
    @poam_risk = @poam_document.poam_risks.build
  end

  # A threat ID the form cannot store as valid OSCAL is refused: nothing is
  # saved, and the form comes back with a message naming the value and with the
  # operator's other fields as typed.
  rescue_from RiskCollectionParams::FormRowInvalid do |e|
    @poam_risk ||= @poam_document.poam_risks.build
    @poam_risk.assign_attributes(params.require(:poam_risk).permit(*SCALAR_FIELDS))
    flash.now[:error] = e.message
    render(@poam_risk.persisted? ? :edit : :new, status: :unprocessable_content)
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
      render :new, status: :unprocessable_content
    end
  end

  def edit
    # Empty action: renders edit.html.erb; the record is loaded by a set_* before_action.
  end

  def update
    if @poam_risk.update(poam_risk_params)
      audit_log("poam_risk_updated", subject: @poam_risk,
                metadata: { title: @poam_risk.title })
      flash[:success] = "Risk updated"
      redirect_to poam_document_path(@poam_document)
    else
      render :edit, status: :unprocessable_content
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

  POAM_RISK_FORM_COLLECTIONS = %i[threat_ids_data mitigating_factors_data].freeze
  SCALAR_FIELDS = %i[title description statement status impact likelihood deadline remarks
                     blocks_ato condition_expires reopen_trigger].freeze

  def poam_risk_params
    permitted = params.require(:poam_risk).permit(
      *SCALAR_FIELDS, # #1154 added blocks_ato, condition_expires, reopen_trigger
      :collections_present,
      props_data:   [ :name, :value, :class, :ns, :uuid, :remarks ],
      links_data:   [ :href, :rel, :media_type, :text ],
      origins_data: [ :actor_type, :actor_uuid, :role_id ],
      # v1.17.2 — threat IDs and mitigating factors, through the same partial
      # and the same normaliser as the SAR risk card. The API has accepted
      # both since #1092.
      threat_ids_data: THREAT_IDS,
      mitigating_factors_data: MITIGATING_FACTORS
    )
    permitted = normalise_form_risk_collections(permitted, record: @poam_risk,
                                                           collections: POAM_RISK_FORM_COLLECTIONS)

    permitted[:props_data]   = compact_props(permitted[:props_data])     if permitted.key?(:props_data)
    permitted[:links_data]   = compact_links(permitted[:links_data])     if permitted.key?(:links_data)
    permitted[:origins_data] = compact_origins(permitted[:origins_data]) if permitted.key?(:origins_data)
    permitted
  end
end
