# frozen_string_literal: true

# #809 — async aggregation of a boundary's scanner findings into its documents.
# Enqueued by the API "aggregate" action (async mode) and available for scheduled
# runs. The synchronous path lives in HdfAggregationService.
class AggregateFindingsJob < ApplicationJob
  queue_as :default

  def perform(boundary_id)
    boundary = AuthorizationBoundary.find_by(id: boundary_id)
    return unless boundary

    result = HdfAggregationService.new(boundary).aggregate
    Rails.logger.info(
      "[HdfAggregation] boundary=#{boundary_id} ssp=#{result.ssp} sar=#{result.sar} " \
      "sap=#{result.sap} poam=#{result.poam}"
    )
  end
end
