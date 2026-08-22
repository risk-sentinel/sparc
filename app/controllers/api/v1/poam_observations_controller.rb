# frozen_string_literal: true

# #1010 — POA&M observations: what was seen, and when it was seen.
class Api::V1::PoamObservationsController < Api::V1::PoamSubresourcesController
  private

  def model = PoamObservation

  def permitted_fields
    [ :title, :description, :remarks, :collected, :expires,
      { methods_data: [] }, PROPS_SHAPE, LINKS_SHAPE, ORIGINS_SHAPE ]
  end

  def summary_fields(record)
    { collected: record.collected&.utc&.iso8601, expires: record.expires&.utc&.iso8601 }
  end

  def detail_fields(record)
    { linked_item_ids: record.poam_items.ids,
      linked_risk_ids: record.poam_risks.ids }
  end
end
