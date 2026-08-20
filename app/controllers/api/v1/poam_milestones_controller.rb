# frozen_string_literal: true

# #1010 — milestones inside a remediation: the steps in executing it.
#
# Nested two deep, under the document and then the remediation, mirroring the
# web routes. The remediation is resolved through the document's risks, so a
# milestone cannot be attached to a remediation on another POA&M.
class Api::V1::PoamMilestonesController < Api::V1::PoamSubresourcesController
  private

  def model = PoamMilestone

  def permitted_fields
    [ :title, :description, :due_date, :milestone_type, :remarks,
      PROPS_SHAPE, LINKS_SHAPE ]
  end

  def remediation
    @remediation ||= PoamRemediation.joins(:poam_risk)
                                    .where(poam_risks: { poam_document_id: @document.id })
                                    .find(params[:remediation_id])
  end

  def collection = remediation.poam_milestones

  def summary_fields(record)
    { due_date: record.due_date&.to_date&.iso8601, milestone_type: record.milestone_type,
      poam_remediation_id: record.poam_remediation_id }
  end

  def audit_metadata(record)
    { poam_document_id: @document.id, poam_remediation_id: remediation.id,
      title: record.try(:title) }
  end
end
