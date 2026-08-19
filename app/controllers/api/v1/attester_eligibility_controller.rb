# frozen_string_literal: true

# Who may attest on a boundary, and under which role (#981).
#
# The evidence form computes this server-side for one boundary and used to leave
# it behind when the boundary select changed, offering a role the server would
# then correctly refuse. This is the endpoint that keeps the two in step, and the
# api-first half of it: every user-facing function gets an Api::V1 surface, with
# the UI as a thin client.
#
# Shares AttesterEligibilityService with the session-authenticated web endpoint
# and with the form partial itself, so the thing that OFFERS an attester/role
# pair and the thing that ACCEPTS it on save cannot disagree. The service only
# assembles; the rule stays on `Attestation`.
#
# Endpoints:
#   GET /api/v1/attestations/eligible                              — instance-wide evidence
#   GET /api/v1/attestations/eligible?authorization_boundary_id=5  — one system
#
# NIST 800-53 Controls:
#   IA-2  Identification and Authentication (Bearer token required)
#   AC-3  Access Enforcement — `evidence.write` on the boundary in question;
#         this discloses who holds an attesting role there, which is not global
#         reference data the way catalog content is.
#   AC-6  Least Privilege — eligibility derives from the `evidence.attest`
#         permission at a scope that reaches this boundary, never a role list.
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class Api::V1::AttesterEligibilityController < Api::V1::BaseController
  # GET /api/v1/attestations/eligible
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
