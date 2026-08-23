# frozen_string_literal: true

# #860 — inspect the entitlement sync, and preview it before trusting it.
#
#   GET  /api/v1/entitlement_sync
#   POST /api/v1/entitlement_sync/preview
#
# The epic asks for a dry run to exist BEFORE `authoritative` is switched on,
# and this is it. The question an operator actually has is not "is the config
# valid" but "if I turn this on, what happens to my people?" — and the only
# honest way to answer it is to compute the real plan with the real resolver
# against the real estate, and then not apply it.
#
# `preview` therefore calls EntitlementSync#dry_run, the same object the login
# path calls #apply on. A separate "simulation" would be a second implementation
# that agrees with the first until the day it does not, which is precisely when
# someone is relying on it.
#
# NIST 800-53 Controls:
#   AC-2 Account Management, AC-3 Access Enforcement, AC-6 Least Privilege
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class Api::V1::EntitlementSyncController < Api::V1::BaseController
  before_action :authorize_admin!

  # GET /api/v1/entitlement_sync
  #
  # Configuration and how much of the estate the sync currently owns.
  def show
    render json: {
      data: {
        mode: SparcConfig.oidc_sync_mode,
        modes: EntitlementSync::MODES,
        claim: SparcConfig.oidc_grants_claim,
        prefix: SparcConfig.oidc_grants_prefix,
        instance_roles_allowed: SparcConfig.oidc_instance_roles,
        max_revoke_pct: SparcConfig.oidc_sync_max_revoke_pct,
        oidc_scopes: SparcConfig.oidc_scopes,
        # The scope is a request; the IdP decides what it releases. An operator
        # debugging "no grants arrive" almost always has the claim configured
        # and the scope missing, so say plainly whether it was asked for.
        grants_scope_requested: SparcConfig.oidc_scopes.split.include?("groups"),
        managed: {
          user_roles: UserRole.where(source: "idp").count,
          organization_memberships: OrganizationMembership.where(source: "idp").count
        }
      }
    }
  end

  # POST /api/v1/entitlement_sync/preview
  #
  # Body: { user_id:, grants: ["sparc:boundary:acme:acme-prod:isso", ...], mode: }
  #
  # Applies nothing. `mode` overrides the configured one so an operator can ask
  # "what would authoritative do?" while still running in bootstrap.
  def preview
    # permit_strictly, like every other Api::V1 body — a field this endpoint does
    # not accept is REFUSED rather than discarded (#995). It also gives the
    # claim-presence check below something reliable to read: `permit` keeps a
    # key only when it was actually submitted.
    body = permit_strictly(:preview, :user_id, :mode, grants: [])

    # RecordNotFound is rescued by Api::V1::BaseController into the standard 404
    # envelope, so this uses the raising finder rather than inventing a second
    # shape for the same outcome.
    user = User.find(body.require(:user_id))

    mode = body[:mode].presence || SparcConfig.oidc_sync_mode
    unless EntitlementSync::MODES.include?(mode)
      return render json: {
        error: "Unknown sync mode #{mode.inspect}",
        expected: EntitlementSync::MODES
      }, status: :unprocessable_entity
    end

    # `grants` absent entirely means "the claim was not in the token", which is
    # a different question from "the claim was empty" and must be previewable as
    # such — it is the misconfiguration this feature most often meets.
    #
    # `permit` preserves a submitted empty array rather than dropping it
    # (verified: `permit(grants: [])` over `{grants: []}` yields a hash where
    # `key?(:grants)` is true, and over `{}` yields one where it is false), so
    # the permitted body is a faithful record of what the caller actually sent.
    claim_present = body.key?(:grants)
    plan = EntitlementSync.new(user: user, claim_values: Array(body[:grants]),
                               claim_present: claim_present, mode: mode).dry_run

    render json: { data: serialize_plan(plan, user) }
  end

  private

  def serialize_plan(plan, user)
    {
      user: { id: user.id, email: user.email },
      mode: plan.mode,
      dry_run: true,
      summary: plan.summary,
      error: plan.error,
      blocked_reason: plan.blocked_reason,
      changes: plan.changes.map { |change| serialize_change(change) },
      unmatched: plan.unmatched.map { |r| { grant: r.raw, reason: r.error } }
    }.compact
  end

  def serialize_change(change)
    {
      action: change.action.to_s,
      target: change.target_type.to_s,
      role: change.role_name,
      organization: change.organization&.slug,
      authorization_boundary: change.authorization_boundary&.slug,
      reason: change.reason
    }.compact
  end
end
