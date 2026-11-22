# frozen_string_literal: true

# #1390 — what the boundary's FedRAMP API controllers share
# (Api::V1::FedrampStatementsController, ...SignificantChangesController,
# ...IncidentsController): the boundary from the path (id, UUID or slug), the
# FedRAMP switch, and a permission check on that boundary that an instance
# administrator passes.
module FedrampApiResource
  extend ActiveSupport::Concern
  include RequiresFedramp

  UUID_FORMAT = /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/

  private

  def set_boundary
    key = params[:id].to_s
    @boundary =
      if key.match?(/\A\d+\z/)
        AuthorizationBoundary.find(key)
      elsif key.match?(UUID_FORMAT)
        AuthorizationBoundary.find_by(uuid: key.downcase) || AuthorizationBoundary.find_by!(slug: key)
      else
        AuthorizationBoundary.find_by!(slug: key)
      end
  end

  def authorize_boundary_permission!(key, message)
    return if current_user.instance_administrator?
    return if current_user.has_permission?(key, authorization_boundary_id: @boundary.id)

    raise Authorization::NotAuthorizedError, message
  end
end
