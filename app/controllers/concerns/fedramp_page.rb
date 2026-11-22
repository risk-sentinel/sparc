# frozen_string_literal: true

# #1390 — what the boundary's FedRAMP pages share (FedrampStatementsController,
# FedrampSignificantChangesController, FedrampIncidentsController): the
# boundary from the path, the FedRAMP switch, and whether the signed-in user
# holds a permission on the boundary (all are offered with sign-in off).
module FedrampPage
  extend ActiveSupport::Concern
  include RequiresFedramp

  included do
    helper_method :boundary_permission?
  end

  private

  def set_boundary
    key = params[:id]
    @boundary = key.to_s.match?(/\A\d+\z/) ? AuthorizationBoundary.find(key) : AuthorizationBoundary.find_by!(slug: key)
  end

  def boundary_permission?(key)
    !SparcConfig.any_auth_enabled? || current_user&.has_permission?(key, authorization_boundary_id: @boundary.id) || false
  end
end
