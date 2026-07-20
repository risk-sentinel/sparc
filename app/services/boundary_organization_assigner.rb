# frozen_string_literal: true

# Assigns an AuthorizationBoundary to an Organization (or clears it), enforcing
# the #770 bug 6 authorization matrix in one place so the admin UI and the
# Api::V1 endpoint stay in agreement (SPARC api-first rule).
#
# Rules (NIST AC-3 Access Enforcement, AC-6 Least Privilege):
#   - Instance admin: may assign an unassigned boundary, or MOVE one between
#     organizations, or clear the association.
#   - Non-admin: may assign an UNASSIGNED boundary only, and only into an
#     organization they org-admin. Moving a boundary that already belongs to a
#     different organization is instance-admin-only.
#
# Raises NotAuthorizedError (mapped to 403 by the API base controller) when the
# actor is not permitted; the message distinguishes "move requires admin" from
# a plain authorization failure so callers can surface an actionable reason.
class BoundaryOrganizationAssigner
  # Authorization::NotAuthorizedError is mapped to 403 by both the web
  # (Authorization concern) and the API base controller.
  AuthError = Authorization::NotAuthorizedError
  class MoveRequiresAdminError < Authorization::NotAuthorizedError; end

  def initialize(boundary:, organization:, actor:)
    @boundary = boundary
    @organization = organization # may be nil to clear the association
    @actor = actor
  end

  # Returns the updated boundary. Raises on authorization failure or invalid save.
  def call
    authorize!
    @boundary.update!(organization: @organization)
    @boundary
  end

  # True when the boundary is currently in a different organization than the
  # target (including clearing an assigned boundary). A move, not a first
  # assignment.
  def moving_between_organizations?
    @boundary.organization_id.present? &&
      @boundary.organization_id != @organization&.id
  end

  private

  def authorize!
    return if @actor.admin?

    if moving_between_organizations?
      raise MoveRequiresAdminError,
        "Only an instance admin can move a boundary between organizations"
    end

    unless @boundary.organization_id.nil? && @actor.org_admin_of?(@organization)
      raise AuthError,
        "Not authorized to assign this boundary to the organization"
    end
  end
end
