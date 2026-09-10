# frozen_string_literal: true

# #860 / #842 — reconcile a user's memberships with what the IdP says.
#
# Built dry-run first, deliberately. The plan is computed by one code path and
# then either reported or applied, so what an administrator previews is what
# runs — not a second implementation that agrees until it does not.
#
# ── The failure mode this exists to prevent ───────────────────────────────
#
# In `authoritative` mode a naive diff reads "no grants in the claim" as "revoke
# everything." A scope filter typo, a renamed claim or an IdP upgrade would then
# silently de-provision an entire customer at their next login, and the symptom
# — nobody can do anything — points nowhere near a claims change. Four defences,
# in the order they bite:
#
#   1. A MISSING claim is an error and syncs nothing. Only an EMPTY claim means
#      "this person has no grants." Those are different states and the caller
#      must tell them apart; `claim_present:` is not optional for that reason.
#   2. Revocation is scoped to `source: "idp"`. A membership an administrator
#      created is never removed by a sync, whatever the directory says. This
#      bounds the blast radius BY CONSTRUCTION rather than by a threshold.
#   3. Instance admin (`users.admin`) is not reachable from any grant, so
#      recovery is always possible. See IdpGrantResolver.
#
# There is deliberately NO ceiling on how much a single sync may revoke (#1059).
# The user gets what the IdP sends: a grant that appeared is gained, a grant that
# is gone is lost. A threshold that applied only PART of a plan would leave SPARC
# and the directory disagreeing about who holds what, which is the exact state
# this class exists to prevent — and being all-or-nothing, it dropped the
# ADDITIONS too, so a user whose access legitimately changed a lot got nothing.
#
# ── What it will not overwrite ────────────────────────────────────────────
#
# `organization_memberships` is UNIQUE on (organization_id, user_id): a user
# holds exactly one role per organization. An IdP grant naming a different role
# than an ADMINISTRATOR-set one is therefore a conflict, and it is reported
# rather than applied. Quietly winning would let a directory silently demote or
# promote someone an administrator had deliberately placed.
class EntitlementSync
  MODES = %w[off bootstrap authoritative].freeze

  # One intended change. `action` is :add, :update, :unchanged, :revoke or
  # :conflict; `applied` says whether it actually happened.
  Change = Struct.new(:action, :target_type, :role_name, :organization, :authorization_boundary,
                      :reason, :applied, keyword_init: true)

  # The whole outcome. A plan is returned by both dry_run and apply — the same
  # shape, so a caller cannot accidentally treat one as the other.
  Plan = Struct.new(:mode, :dry_run, :changes, :unmatched, :error,
                    keyword_init: true) do
    def add        = changes.select { |c| c.action == :add }
    def update     = changes.select { |c| c.action == :update }
    def revoke     = changes.select { |c| c.action == :revoke }
    def unchanged  = changes.select { |c| c.action == :unchanged }
    def conflicts  = changes.select { |c| c.action == :conflict }
    def error?     = error.present?
    def applied_count = changes.count(&:applied)

    # "3 added, 1 revoked, 2 unmatched" — the diff, not just the result.
    def summary
      "#{add.size} to add, #{update.size} to update, #{revoke.size} to revoke, " \
        "#{unchanged.size} unchanged, #{conflicts.size} conflicting, #{unmatched.size} unmatched"
    end
  end

  SOURCE = "idp"

  # `claim_present:` distinguishes "the IdP sent no grants" from "the claim was
  # not in the token at all". Defaulted to false so a caller that forgets errs
  # toward doing nothing rather than toward revoking everything.
  def initialize(user:, claim_values: [], claim_present: false, mode: nil, resolver: IdpGrantResolver.new)
    @user = user
    @claim_values = claim_values
    @claim_present = claim_present
    @mode = (mode || SparcConfig.oidc_sync_mode).to_s
    @resolver = resolver
  end

  def dry_run = build_plan(dry_run: true)

  def apply
    plan = build_plan(dry_run: false)
    return plan if plan.error? || @mode == "off"

    ActiveRecord::Base.transaction { plan.changes.each { |change| apply_change(change) } }
    audit!(plan)
    plan
  end

  private

  attr_reader :user, :claim_values, :claim_present, :mode, :resolver

  # One event per decision, with the reason — the epic's requirement, and the
  # granularity an assessor needs: "these rights were conferred by the IdP on
  # this date, and these were refused because the boundary did not exist."
  #
  # Emitted OUTSIDE the transaction that applied the changes. An audit failure
  # must not roll back a membership change that already succeeded, or the
  # records and reality diverge in the direction that hides work.
  def audit!(plan)
    plan.changes.each do |change|
      action = case change.action
      when :add, :update then "idp_grant_applied"
      when :revoke       then "idp_grant_revoked"
      when :conflict     then "idp_grant_skipped"
      else                    nil # :unchanged — nothing happened, so nothing to record
      end
      next if action.nil?

      AuditEvent.log(user: user, action: action, provider: "oidc",
                     metadata: change_metadata(change))
    end

    plan.unmatched.each do |resolution|
      AuditEvent.log(user: user, action: "idp_grant_skipped", provider: "oidc",
                     metadata: { grant: resolution.raw, reason: resolution.error })
    end
  end

  def change_metadata(change)
    {
      grant_action: change.action.to_s,
      target: change.target_type.to_s,
      role: change.role_name,
      organization: change.organization&.slug,
      authorization_boundary: change.authorization_boundary&.slug,
      reason: change.reason
    }.compact
  end

  def build_plan(dry_run:)
    return plan_with(dry_run, error: "unknown sync mode #{mode.inspect}") unless MODES.include?(mode)
    return plan_with(dry_run) if mode == "off"

    unless claim_present
      # Defence 1. Not an empty grant set — an absent claim, which says nothing
      # about this user's entitlements and must therefore change nothing.
      return plan_with(dry_run, error: "the grants claim #{SparcConfig.oidc_grants_claim.inspect} " \
                                       "was not present in the token; nothing was synced")
    end

    resolutions = resolver.resolve_all(IdpGrant.parse_all(claim_values))
    resolved, unmatched = resolutions.partition(&:resolved?)

    changes = additions(resolved)
    changes += revocations(resolved) if mode == "authoritative"

    plan_with(dry_run, changes: changes, unmatched: unmatched)
  end

  # ── Additions ───────────────────────────────────────────────────────────

  def additions(resolutions)
    resolutions.map do |resolution|
      resolution.target_type == :user_role ? user_role_change(resolution) : org_change(resolution)
    end
  end

  def user_role_change(resolution)
    existing = user.user_roles.find_by(role_id: resolution.role.id,
                                       authorization_boundary_id: resolution.authorization_boundary&.id)
    # Already held. If an administrator granted it, it stays theirs — the sync
    # does not take ownership of a row it did not create, because doing so would
    # make it revocable later by a directory that never granted it.
    return change(:unchanged, resolution) if existing

    change(:add, resolution)
  end

  def org_change(resolution)
    existing = user.organization_memberships.find_by(organization_id: resolution.organization.id)
    return change(:add, resolution) if existing.nil?
    return change(:unchanged, resolution) if existing.role == resolution.role_name

    # A different role is already recorded. Whose it is decides what happens.
    if existing.source == SOURCE
      change(:update, resolution)
    else
      change(:conflict, resolution,
             reason: "an administrator set #{existing.role.inspect} for this organization; " \
                     "the IdP grant of #{resolution.role_name.inspect} was not applied")
    end
  end

  # ── Revocations (authoritative only) ────────────────────────────────────

  def revocations(resolved)
    wanted_roles = resolved.select { |r| r.target_type == :user_role }
                           .map { |r| [ r.role.id, r.authorization_boundary&.id ] }.to_set
    wanted_orgs  = resolved.select { |r| r.target_type == :organization_membership }
                           .map { |r| r.organization.id }.to_set

    stale_user_roles(wanted_roles) + stale_org_memberships(wanted_orgs)
  end

  # Defence 2, and the reason `source` had to exist on both tables: only rows
  # this sync created are candidates for removal.
  def stale_user_roles(wanted)
    user.user_roles.where(source: SOURCE).includes(:role, :authorization_boundary).filter_map do |ur|
      next if wanted.include?([ ur.role_id, ur.authorization_boundary_id ])

      Change.new(action: :revoke, target_type: :user_role, role_name: ur.role.name,
                 authorization_boundary: ur.authorization_boundary, applied: false)
    end
  end

  def stale_org_memberships(wanted)
    user.organization_memberships.where(source: SOURCE).includes(:organization).filter_map do |om|
      next if wanted.include?(om.organization_id)

      Change.new(action: :revoke, target_type: :organization_membership, role_name: om.role,
                 organization: om.organization, applied: false)
    end
  end

  # ── Application ─────────────────────────────────────────────────────────

  def apply_change(change)
    case change.action
    when :add       then create_membership(change)
    when :update    then update_membership(change)
    when :revoke    then destroy_membership(change)
    else return # :unchanged and :conflict write nothing, by definition
    end
    change.applied = true
  end

  def create_membership(change)
    if change.target_type == :user_role
      user.user_roles.create!(role: Role.find_by!(name: change.role_name),
                              authorization_boundary: change.authorization_boundary, source: SOURCE)
    else
      user.organization_memberships.create!(organization: change.organization,
                                            role: change.role_name, source: SOURCE)
    end
  end

  def update_membership(change)
    user.organization_memberships
        .find_by!(organization_id: change.organization.id)
        .update!(role: change.role_name, source: SOURCE)
  end

  def destroy_membership(change)
    if change.target_type == :user_role
      user.user_roles.where(source: SOURCE, role: Role.find_by(name: change.role_name),
                            authorization_boundary_id: change.authorization_boundary&.id).destroy_all
    else
      user.organization_memberships
          .where(source: SOURCE, organization_id: change.organization.id).destroy_all
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────────

  def change(action, resolution, reason: nil)
    Change.new(action: action, target_type: resolution.target_type, role_name: resolution.role_name,
               organization: resolution.organization,
               authorization_boundary: resolution.authorization_boundary,
               reason: reason, applied: false)
  end

  def plan_with(dry_run, changes: [], unmatched: [], error: nil)
    Plan.new(mode: mode, dry_run: dry_run, changes: changes, unmatched: unmatched, error: error)
  end
end
