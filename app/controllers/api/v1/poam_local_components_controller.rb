# frozen_string_literal: true

# #1010 — components defined locally on a POA&M, for systems whose component
# inventory does not come from an SSP.
class Api::V1::PoamLocalComponentsController < Api::V1::PoamSubresourcesController
  private

  def model = PoamLocalComponent

  def permitted_fields
    [ :title, :description, :component_type, :purpose, :remarks,
      :status_state, :status_remarks, PROPS_SHAPE, LINKS_SHAPE ]
  end

  def summary_fields(record)
    { component_type: record.component_type, status_state: record.status_state }
  end

  def detail_fields(record)
    { purpose: record.purpose, status_remarks: record.status_remarks }
  end
end
