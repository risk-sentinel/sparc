# frozen_string_literal: true

# #940 — GET /api/v1/authorization_boundaries/:authorization_boundary_id/readiness
#
# Read-only completeness report: what does SPARC actually know about this
# boundary? Sections map onto the decisions in the wiki's "Adopting OSCAL"
# guide, so a gap points at the page that explains how to close it.
#
# Strictly read-only — it never mutates boundary state, which is what makes it
# safe to poll from a pipeline or render on every page load.
class Api::V1::BoundaryReadinessController < Api::V1::BaseController
  before_action :set_boundary

  def show
    authorize_permission!("authorization_boundaries.read", authorization_boundary_id: @boundary.id)

    render json: { data: BoundaryReadinessService.new(@boundary).report }
  end

  private

  def set_boundary
    @boundary = AuthorizationBoundary.find_by!(id: params[:authorization_boundary_id])
  rescue ActiveRecord::RecordNotFound
    @boundary = AuthorizationBoundary.find_by!(slug: params[:authorization_boundary_id])
  end
end
