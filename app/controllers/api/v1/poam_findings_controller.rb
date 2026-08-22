# frozen_string_literal: true

# #1010 — POA&M findings: the assessment conclusions an item answers.
#
# `target_data` keeps the OSCAL spelling — `type`, `target-id`, and a nested
# `status` of `state`/`remarks` — rather than inventing a second name for data
# that has to round-trip to OSCAL unchanged.
#
# The web path compacts blank rows out of the OSCAL arrays before saving,
# because an HTML form submits empty rows for the inputs the user did not fill
# in. A JSON caller sends what it means, so nothing is stripped here.
class Api::V1::PoamFindingsController < Api::V1::PoamSubresourcesController
  private

  def model = PoamFinding

  def permitted_fields
    [ :title, :description, :remarks, :implementation_statement_uuid,
      PROPS_SHAPE, LINKS_SHAPE, ORIGINS_SHAPE,
      { target_data: [ :type, :"target-id", { status: %i[state remarks] } ] } ]
  end

  def detail_fields(record)
    { implementation_statement_uuid: record.implementation_statement_uuid,
      target_data: record.try(:target_data),
      linked_item_ids: record.poam_items.ids,
      linked_observation_ids: record.poam_observations.ids }
  end
end
