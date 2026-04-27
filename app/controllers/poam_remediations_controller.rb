# Admin UI for OSCAL POA&M risk-response (remediations) entries (#423).
#
# A remediation belongs to a `PoamRisk` and represents the planned
# response to that risk. Has many `PoamMilestone`s representing
# progress markers. Routed flat under poam_documents (the parent risk
# is selected on the form rather than nested in the URL) for shorter,
# friendlier paths.
class PoamRemediationsController < ApplicationController
  include OscalExtensibilityParams

  before_action :set_poam_document
  before_action :set_poam_remediation, only: %i[edit update destroy]

  def new
    @poam_remediation = PoamRemediation.new(poam_risk_id: params[:poam_risk_id])
    load_risk_options
  end

  def create
    risk = @poam_document.poam_risks.find(params[:poam_remediation][:poam_risk_id])
    @poam_remediation = risk.poam_remediations.build(poam_remediation_params)
    @poam_remediation.uuid ||= SecureRandom.uuid

    if @poam_remediation.save
      audit_log("poam_remediation_created", subject: @poam_remediation,
                metadata: { title: @poam_remediation.title, poam_risk_id: risk.id })
      flash[:success] = "Remediation added"
      redirect_to poam_document_path(@poam_document)
    else
      load_risk_options
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_risk_options
  end

  def update
    if @poam_remediation.update(poam_remediation_params)
      audit_log("poam_remediation_updated", subject: @poam_remediation,
                metadata: { title: @poam_remediation.title })
      flash[:success] = "Remediation updated"
      redirect_to poam_document_path(@poam_document)
    else
      load_risk_options
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    title = @poam_remediation.title
    audit_log("poam_remediation_deleted", subject: @poam_remediation, metadata: { title: title })
    @poam_remediation.destroy
    flash[:success] = "Remediation \"#{title}\" removed"
    redirect_to poam_document_path(@poam_document)
  end

  private

  def set_poam_document
    @poam_document = PoamDocument.find_by!(slug: params[:poam_document_id])
  end

  def set_poam_remediation
    @poam_remediation = PoamRemediation.joins(:poam_risk)
                                        .where(poam_risks: { poam_document_id: @poam_document.id })
                                        .find(params[:id])
  end

  def load_risk_options
    @available_risks = @poam_document.poam_risks.order(:title)
  end

  def poam_remediation_params
    permitted = params.require(:poam_remediation).permit(
      :title, :description, :lifecycle, :remarks, :poam_risk_id,
      props_data:   [ :name, :value, :class, :ns, :uuid, :remarks ],
      links_data:   [ :href, :rel, :media_type, :text ],
      origins_data: [ :actor_type, :actor_uuid, :role_id ]
    )
    permitted[:props_data]   = compact_props(permitted[:props_data])     if permitted.key?(:props_data)
    permitted[:links_data]   = compact_links(permitted[:links_data])     if permitted.key?(:links_data)
    permitted[:origins_data] = compact_origins(permitted[:origins_data]) if permitted.key?(:origins_data)
    permitted.except(:poam_risk_id) # already used to scope the build
  end
end
