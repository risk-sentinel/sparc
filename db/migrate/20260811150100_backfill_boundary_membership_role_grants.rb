# #707 / #919 — give every EXISTING boundary roster member the permissions their
# role implies.
#
# Until now the roster and the permission model never met: an
# AuthorizationBoundaryMembership recorded who was on a boundary, while
# UserRole + Role recorded what a user could do, and creating the first never
# created the second. Measured on a seeded instance before the fix, a member
# added as `isso` had 1 membership row, 0 user_role rows, and
# has_permission?("poam.write", authorization_boundary_id:) returned false.
#
# The model callback now provisions the grant on create/update, but callbacks
# only fire on writes. Without this backfill every member who joined before the
# deploy stays at zero permissions — and because #919 added guards to the
# boundary-scoped controllers in the same release, they would be actively locked
# out of work they could previously do.
#
# Deferred (see app/lib/deferred_data_migration.rb): the schema_migrations row is
# recorded at db:migrate time and the body runs post-boot, so an instance with a
# large roster still comes up immediately.
#
# ── Idempotency and resume-from-partial ────────────────────────────────────
#
#   * The work is delegated to BoundaryMembershipRoleSync.sync!, which is
#     find_or_create_by on (user, role, boundary) and therefore safe to re-run.
#     A membership already synced is a no-op rather than a duplicate.
#   * sync! also REVOKES any stale membership-derived grant on the same boundary
#     before creating the new one, so a re-run after a partial failure converges
#     rather than accumulating.
#   * Rows with no linked user (a roster entry naming someone not yet
#     provisioned) are skipped, not errored — that is a legitimate state.
#
# ── What it deliberately does NOT do ───────────────────────────────────────
#
# It never touches a grant whose source is "manual". An administrator's explicit
# assignment is a separate decision from roster membership, and a data migration
# quietly revoking one would be indistinguishable from a bug. Only rows this
# system owns (source "membership") are created or removed.
#
# It does not invent roles. A membership whose role has no canonical Role — a
# custom SPARC_AUTH_BOUNDARY_ROLES value, say — grants nothing and is counted as
# unmapped, so an operator can see the gap rather than having a role guessed for
# them.
#
# ── Blast radius, stated plainly ───────────────────────────────────────────
#
# This grants permissions to every existing roster member at once, the moment it
# runs. That is the intended repair, but it IS a live authorization change across
# every boundary simultaneously, not a gradual one.
class BackfillBoundaryMembershipRoleGrants < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  def up
    defer_data_migration do
      backfill_membership_grants
    end
  end

  # Deliberately empty. Rolling back would strip permissions from every roster
  # member, which is a far more damaging state than leaving correct grants in
  # place — and the grants are indistinguishable from the ones the callback
  # would recreate on the next roster write anyway.
  def down
    # intentionally empty
  end

  def backfill_membership_grants
    granted  = 0
    skipped  = 0
    unmapped = 0

    AuthorizationBoundaryMembership.find_each(batch_size: 200) do |membership|
      if membership.user_id.blank?
        skipped += 1
        next
      end

      if BoundaryMembershipRoleSync.canonical_role_for(membership.role).nil?
        unmapped += 1
        next
      end

      BoundaryMembershipRoleSync.sync!(membership)
      granted += 1
    end

    say "boundary membership grants: #{granted} synced, #{skipped} without a linked user, " \
        "#{unmapped} with a role that maps to no canonical Role"
    granted
  end
end
