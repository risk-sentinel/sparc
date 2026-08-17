# frozen_string_literal: true

# Which authorization boundaries a user may ATTACH a document to (#929).
#
# This existed inline in two partials and asked the wrong question. Both
# `shared/_boundary_picker` and `cdef_documents/_scope_picker` joined the
# LEGACY roster:
#
#   AuthorizationBoundary.joins(:authorization_boundary_memberships)
#     .where(authorization_boundary_memberships: { user_id: current_user.id })
#
# while scoping and permissions run off the OTHER role system — `UserRole`,
# reached as `current_user.authorization_boundaries`
# (see BoundaryScopedDocument#boundary_scoped_relation). The two never met.
#
# `AuthorizationBoundaryMembership#user_id` is optional and a roster entry is
# routinely created by name/email alone, so the join returns nothing for a
# member who was added the normal way. On the demo estate all seven roster rows
# had `user_id: nil` and the admin had zero `user_roles`, so the query returned
# an empty set for EVERY user — and `<% if boundaries.any? %>` then removed the
# field from the page entirely. A boundary could not be chosen at upload by
# anyone, which is why every SSP/SAP/SAR/POA&M arrived with no boundary and
# #952's orphans exist at all.
#
# The rule here mirrors `boundary_scoped_relation` exactly, so what a user can
# be OFFERED cannot drift from what a user can SEE:
#   - Instance-Admin -> every boundary.
#   - Otherwise      -> boundaries granted via UserRole, UNION boundaries whose
#                       legacy roster row is linked to this user. The union
#                       keeps pre-#707 rosters working while the UserRole path
#                       becomes canonical.
#
# Being offered a boundary is not permission to write to it. The write itself
# is authorized against the TARGET boundary in
# BoundaryScopedDocument#authorize_document_write! and its Api::V1 twin.
#
# NIST 800-53: AC-3 Access Enforcement, AC-6 Least Privilege.
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
module BoundaryPickerHelper
  # Boundaries `user` may attach a document to, ordered by name.
  # Returns AuthorizationBoundary.none for a nil user (signed-out render).
  def assignable_boundaries(user)
    return AuthorizationBoundary.none if user.nil?
    return AuthorizationBoundary.order(:name) if user.admin?

    granted = user.authorization_boundaries.ids
    rostered = AuthorizationBoundary
                 .joins(:authorization_boundary_memberships)
                 .where(authorization_boundary_memberships: { user_id: user.id })
                 .ids

    AuthorizationBoundary.where(id: (granted + rostered).uniq).order(:name)
  end
end
