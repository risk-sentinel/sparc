# frozen_string_literal: true

# #1010 — POA&M remediations: what will be done about a risk.
#
# A remediation belongs to a RISK, not to the document, but it is routed under
# the document because that is the object a caller holds. The collection is
# therefore scoped through the document's risks, which also makes
# cross-document access impossible by construction rather than by a check.
class Api::V1::PoamRemediationsController < Api::V1::PoamSubresourcesController
  private

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
