# frozen_string_literal: true

# #707 / #919 — make boundary roster membership actually grant permissions.
#
# SPARC has carried two role systems that never met:
#
#   * AuthorizationBoundaryMembership — the roster. Who is on a boundary, with a
#     role string. Surfaced in the UI, documented in wiki/RBAC.md.
#   * UserRole + Role — the permission model. What a user may DO, read by
#     User#has_permission? and therefore by every authorize_permission! guard.
#
# Creating the first never created the second. Measured before this change: a
# user added to a boundary as `isso` had 1 membership row, 0 user_role rows, and
# `has_permission?("poam.write", authorization_boundary_id: b.id)` returned
# false. The roster was decorative.
#
# That was invisible while the boundary-scoped controllers had no guards — a
# roster member could act regardless, because nothing asked. #919 added the
# guards, which turned a latent inconsistency into a lockout: the guard asks,
# gets false, and refuses a legitimate member. Fixing the roster is therefore
# part of that change rather than a follow-up, because shipping the guards
# without it would be a regression.
#
# Direction is deliberately one-way: the roster drives permissions, never the
# reverse. An admin may still grant a UserRole directly (source "manual"), and
# this class must never touch those — only the rows it owns (source
# "membership"). Otherwise removing someone from a roster would silently revoke
# an unrelated deliberate grant.
#
# NIST 800-53: AC-2 (account management), AC-3 (access enforcement),
# AC-6 (least privilege — a member receives exactly their role's permissions on
# exactly their boundary, and nothing elsewhere).
class BoundaryMembershipRoleSync
  # Membership vocabulary → canonical Role name, for the three that differ.
  # The other four (ciso, isso, project_member, view_only) are identical in both
  # vocabularies and resolve by exact match.
  ROLE_NAME_MAP = {
    "authorizing_official" => "ao",
    "system_owner"         => "so_iso",
    "assessor"             => "assessor_3pao"
  }.freeze

  MEMBERSHIP_SOURCE = "membership"

  class << self
    # Bring the user's membership-derived grant in line with the membership.
    # Safe to call repeatedly; safe when the membership has no linked user
    # (a roster row can name someone who has not been provisioned yet).
    def sync!(membership)
      return if membership.user_id.blank?

      role = canonical_role_for(membership.role)

      # Drop any previous membership-derived grant on this boundary first, so a
      # ROLE CHANGE does not leave the old permissions behind. This is the case
      # a naive find_or_create would miss.
      revoke!(membership, except_role_id: role&.id)

      return log_unmapped(membership) if role.nil?

      UserRole.find_or_create_by!(
        user_id: membership.user_id,
        role_id: role.id,
        authorization_boundary_id: membership.authorization_boundary_id
      ) { |ur| ur.source = MEMBERSHIP_SOURCE }
    end

    # Remove the membership-derived grant. Never touches a manual grant.
    def revoke!(membership, except_role_id: nil)
      return if membership.user_id.blank?

      scope = UserRole.where(
        user_id: membership.user_id,
        authorization_boundary_id: membership.authorization_boundary_id,
        source: MEMBERSHIP_SOURCE
      )
      scope = scope.where.not(role_id: except_role_id) if except_role_id
      scope.destroy_all
    end

    # Exact match first, so a deployment that configures a custom
    # SPARC_AUTH_BOUNDARY_ROLES entry naming a real canonical role (e.g. `issm`,
    # which is NOT in the membership DEFAULT_ROLES) resolves correctly rather
    # than falling through the alias map.
    def canonical_role_for(membership_role)
      name = membership_role.to_s
      Role.find_by(name: name, scope: "authorization_boundary") ||
        Role.find_by(name: ROLE_NAME_MAP[name], scope: "authorization_boundary")
    end

    private

    # A custom role with no canonical counterpart grants NOTHING — fail closed.
    # Logged rather than raised: a roster edit must not be blocked because an
    # operator invented a role name, but an operator must be able to see why the
    # member has no access.
    def log_unmapped(membership)
      Rails.logger.warn(
        "[BoundaryMembershipRoleSync] Membership role #{membership.role.inspect} on boundary " \
        "#{membership.authorization_boundary_id} maps to no canonical Role, so no permissions " \
        "were granted. Define a matching Role (Admin > Roles) or use one of: " \
        "#{(AuthorizationBoundaryMembership::DEFAULT_ROLES + ROLE_NAME_MAP.keys).uniq.sort.join(', ')}."
      )
      nil
    end
  end
end
