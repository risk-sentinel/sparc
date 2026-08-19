# frozen_string_literal: true

# Session-authenticated attester eligibility for the evidence form (#981).
#
# The Bearer-only API twin (Api::V1::AttesterEligibilityController) excludes
# cookies and CSRF middleware, so the browser cannot call it. Rather than loosen
# the API's auth posture or duplicate the rule, both front doors run
# AttesterEligibilityService — the api-first convention already used by
# ControlLookupsController for the control picker.
class AttesterEligibilityController < ApplicationController
  # GET /attestations/eligible.json?authorization_boundary_id=:id
  #
  # Unlike the control lookup, this is NOT global reference data: it discloses
  # which accounts hold an attesting role on a named boundary. So the caller must
  # hold `evidence.write` there — the same permission that gets them to the form
  # this feeds. Instance-wide evidence (blank boundary) is checked at instance
  # scope, matching how the form itself is reached.
  def index
    boundary_id = params[:authorization_boundary_id].presence
    authorize_permission!("evidence.write", authorization_boundary_id: boundary_id)

    service = AttesterEligibilityService.new(authorization_boundary_id: boundary_id)

    render json: {
      data: service.as_json,
      meta: { authorization_boundary_id: boundary_id }
    }
  end
end
