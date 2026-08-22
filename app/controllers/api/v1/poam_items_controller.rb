# frozen_string_literal: true

# #1010 — POA&M items: the individual entries in the plan of action.
class Api::V1::PoamItemsController < Api::V1::PoamSubresourcesController
  private

  def model = PoamItem

  def permitted_fields
    [ :title, :description, :risk_status, :risk_level,
      :likelihood, :impact, :deadline,
      :internal_notes, :closure_evidence, :remarks,
      # #393 — an item can point at the SSP statement it came from.
      :ssp_control_statement_id,
      PROPS_SHAPE, LINKS_SHAPE, ORIGINS_SHAPE ]
  end

  def summary_fields(record)
    { risk_status: record.risk_status, risk_level: record.risk_level,
      deadline: record.deadline&.to_date&.iso8601 }
  end

  def detail_fields(record)
    { likelihood: record.likelihood, impact: record.impact,
      internal_notes: record.internal_notes, closure_evidence: record.closure_evidence,
      ssp_control_statement_id: record.ssp_control_statement_id,
      linked_risk_ids: record.poam_risks.ids }
  end
end
