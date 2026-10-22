# frozen_string_literal: true

# #1010 — POA&M remediations: what will be done about a risk.
#
# A remediation belongs to a RISK, not to the document, but it is routed under
# the document because that is the object a caller holds. The collection is
# therefore scoped through the document's risks, which also makes
# cross-document access impossible by construction rather than by a check.
class Api::V1::PoamRemediationsController < Api::V1::PoamSubresourcesController
  # A callback of its OWN name. Re-declaring `before_action :authorize_poam_write!,
  # only: :complete` here would REPLACE the base class's declaration (Rails
  # de-duplicates callbacks by name), leaving create/update/destroy unguarded.
  before_action :authorize_and_load_for_complete!, only: :complete

  # POST /api/v1/poam_documents/:poam_document_id/remediations/:id/complete
  #
  # v1.17.2 — the web's Mark completed: OSCAL `lifecycle` becomes `completed`.
  # Already completed is a 422 and nothing changes.
  def complete
    PoamResolutionService.complete!(@record)
    audit_log("poam_remediation_completed", subject: @record, metadata: audit_metadata(@record))
    render json: { data: serialize(@record, detailed: true) }
  rescue PoamResolutionService::Refused => e
    render json: { error: e.message }, status: :unprocessable_content
  end

  private

  def authorize_and_load_for_complete!
    authorize_poam_write!
    set_record
  end

  def model = PoamRemediation

  def permitted_fields
    [ :title, :description, :lifecycle, :remarks, :poam_risk_id,
      PROPS_SHAPE, LINKS_SHAPE, ORIGINS_SHAPE ]
  end

  def collection
    PoamRemediation.joins(:poam_risk)
                   .where(poam_risks: { poam_document_id: @document.id })
  end

  # `collection` is a join, so it cannot build. The risk is resolved through
  # the document, which is what stops a caller attaching a remediation to a
  # risk on someone else's POA&M.
  def build_record
    attributes = record_params
    risk = @document.poam_risks.find(attributes[:poam_risk_id])
    risk.poam_remediations.new(attributes.except(:poam_risk_id))
  end

  def summary_fields(record)
    { lifecycle: record.lifecycle, poam_risk_id: record.poam_risk_id,
      milestone_count: record.poam_milestones.count }
  end
end
