# Session-authenticated control lookup for the evidence control picker (#902).
#
# The equivalent API endpoint (Api::V1::ControlLookupsController) is Bearer-only
# and deliberately excludes cookies and CSRF middleware, so the browser cannot
# call it. Rather than loosen the API's auth posture or duplicate the query,
# both front doors run the same ControlLookupService — the api-first rule with
# the UI as a thin client over a shared service.
#
# Read-only over catalog content, which is global reference data rather than
# boundary-scoped: knowing that AC-2 exists discloses nothing about any system.
# Authentication is still required, since an anonymous caller has no business
# enumerating the deployment's loaded catalogs.
class ControlLookupsController < ApplicationController
  # GET /controls/lookup.json
  def index
    result = ControlLookupService.new(
      q: params[:q],
      family: params[:family],
      limit: params[:limit],
      authorization_boundary_id: params[:authorization_boundary_id]
    ).call

    render json: {
      data: result.controls.map { |c| ControlLookupService.serialize(c) },
      meta: {
        total: result.total,
        limit: result.limit,
        scoped_to_profile: result.scoped_to_profile?,
        profile_title: result.profile&.name
      }
    }
  end
end
