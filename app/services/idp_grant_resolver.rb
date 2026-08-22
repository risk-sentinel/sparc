# frozen_string_literal: true

# #860 / #842 — resolve a parsed grant against what SPARC actually has.
#
# The hard constraint from the epic: **this never creates anything.** A grant
# naming an organization, boundary or role that does not exist is recorded and
# surfaced, never provisioned. Auto-creating would let the IdP mint tenants,
# which inverts who is in control of the estate.
#
# ── Where a grant LANDS, which is not one place ───────────────────────────
#
# SPARC has three representations of "role", and they are not duplicates of one
# another. A resolver that pretended otherwise would write to the wrong table:
#
#   user_roles -> roles                  the AUTHORIZATION record. Role is a FK
#                                        to a permission-carrying Role, scoped
#                                        to a boundary (or NULL for instance
#                                        roles). Carries `source`.
#
#   organization_memberships.role        a STRING from a configurable list
#                                        (OrganizationMembership.available_roles).
#                                        Not a Role FK, different vocabulary.
#                                        `org_admin` here is a real permission
#                                        gate — see User#org_admin_for?.
#
#   authorization_boundary_memberships   DOCUMENTARY, for the SSP. Carries
#                                        user_name/user_email STRINGS and a
#                                        nullable user_id, so it can name a
#                                        person who has no account.
#
# A boundary grant resolves to the first. An org grant resolves to the second.
# **Nothing resolves to the third, ever** — it is content an assessor reads, and
# an IdP sync that overwrote it would destroy the SSP's record of who holds a
# role, replacing a deliberate statement with a directory's current opinion.
#
# ── Instance roles are unreachable by design ──────────────────────────────
#
# The grant format has no instance scope. There is no string an IdP can emit
# that grants an instance-wide role or the `users.admin` break-glass flag, so
# the epic's "never destructive to instance roles" constraint is satisfied by
# construction rather than by a guard that could be forgotten. Recovery is
# therefore always possible: a misconfigured IdP cannot lock the estate out.
class IdpGrantResolver
  # A resolved grant, or a named reason it could not be.
  #
  # `target_type` is :user_role or :organization_membership — the table the sync
  # will write, decided here rather than inferred later.
  Resolution = Struct.new(
    :grant, :target_type, :organization, :authorization_boundary, :role, :role_name, :error,
    keyword_init: true
  ) do
    def resolved? = error.nil?
    def raw = grant&.raw
  end

  # Resolve many, preserving order. Malformed grants short-circuit to their own
  # parse error rather than being re-diagnosed here.
  def resolve_all(grants)
    Array(grants).map { |grant| resolve(grant) }
  end

  def resolve(grant)
    return unresolved(grant, grant.error) unless grant.valid?

    grant.org_scoped? ? resolve_org(grant) : resolve_boundary(grant)
  end

  private

  def resolve_org(grant)
    organization = find_organization(grant.organization_slug)
    return unresolved(grant, "organization #{grant.organization_slug.inspect} not found") if organization.nil?

    # Org roles are strings from a configurable list, not Role records. Compared
    # canonically because the list is operator-supplied and the claim is
    # hand-typed; neither is guaranteed to agree on case.
    role_name = OrganizationMembership.available_roles.find do |candidate|
      IdpGrant.canonicalize(candidate) == grant.role_name
    end
    if role_name.nil?
      return unresolved(grant, "organization role #{grant.role_name.inspect} is not one of " \
                               "#{OrganizationMembership.available_roles.join(', ')}")
    end

    Resolution.new(grant: grant, target_type: :organization_membership,
                   organization: organization, role_name: role_name)
  end

  def resolve_boundary(grant)
    organization = find_organization(grant.organization_slug)
    return unresolved(grant, "organization #{grant.organization_slug.inspect} not found") if organization.nil?

    boundary = AuthorizationBoundary.find_by(slug: grant.boundary_slug)
    return unresolved(grant, "authorization boundary #{grant.boundary_slug.inspect} not found") if boundary.nil?

    # The check the org segment exists for. Boundary slugs are globally unique,
    # so the boundary resolved above is the right RECORD — but if the grant names
    # a different organization than the one that owns it, the person who wrote
    # the group meant something else, and applying it anyway would grant access
    # inside a tenant they did not name.
    if boundary.organization_id != organization.id
      return unresolved(grant, "organization #{grant.organization_slug.inspect} does not own " \
                               "authorization boundary #{grant.boundary_slug.inspect}")
    end

    role = Role.find_by(name: grant.role_name)
    return unresolved(grant, "role #{grant.role_name.inspect} not found") if role.nil?

    # UserRole validates this pairing too, but failing here gives the
    # administrator a reason in the unmatched queue instead of a validation
    # error buried in a job log.
    unless role.scope == "authorization_boundary"
      return unresolved(grant, "role #{grant.role_name.inspect} is #{role.scope}-scoped and " \
                               "cannot be granted on an authorization boundary")
    end

    Resolution.new(grant: grant, target_type: :user_role, organization: organization,
                   authorization_boundary: boundary, role: role, role_name: role.name)
  end

  # Slugs are generated lowercase, and IdpGrant has already canonicalised the
  # claim value, so this is a direct lookup rather than a scan.
  def find_organization(slug) = Organization.find_by(slug: slug)

  def unresolved(grant, reason) = Resolution.new(grant: grant, error: reason)
end
