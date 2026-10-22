# frozen_string_literal: true

module AuthorizationHelper
  # Check if the current user can perform write operations on catalogs.
  # Returns true when:
  #   1. Auth is disabled (backward compatible — show buttons to everyone)
  #   2. User is an Instance Admin
  #   3. User has the catalogs.write permission
  def can_write_catalogs?
    !SparcConfig.any_auth_enabled? || current_user&.instance_administrator? || current_user&.has_permission?("catalogs.write")
  end

  # Check if the current user can perform write operations on control mappings.
  def can_write_mappings?
    !SparcConfig.any_auth_enabled? || current_user&.instance_administrator? || current_user&.has_permission?("mappings.write")
  end

  # #928 — mirrors ProfileDocumentsController#authorize_profiles_write!, so the
  # catalog picker is only drawn for a caller the guard would actually let
  # through. Unscoped `profiles.write`: profiles are instance-level, not
  # boundary-scoped.
  def can_write_profiles?
    !SparcConfig.any_auth_enabled? || current_user&.instance_administrator? || current_user&.has_permission?("profiles.write")
  end

  # Check if the current user can perform write operations on converters.
  def can_write_converters?
    !SparcConfig.any_auth_enabled? || current_user&.instance_administrator? || current_user&.has_permission?("converters.write")
  end

  # #629 — bulk delete is instance-admin-only; mirror authorize_admin! so the
  # UI only renders the controls when the action would actually be allowed.
  def can_bulk_delete?
    !SparcConfig.any_auth_enabled? || current_user&.instance_administrator?
  end

  # #1247 — the boundary list shows an action only to someone the server would
  # let do it. These mirror AuthorizationBoundaryAccess and the destroy guard;
  # hiding a button is not access control, the guards are (#1244).
  def can_edit_boundary?(boundary)
    !SparcConfig.any_auth_enabled? ||
      current_user&.has_permission?(AuthorizationBoundary::WRITE_PERMISSION, authorization_boundary_id: boundary.id)
  end

  def can_create_boundary?
    !SparcConfig.any_auth_enabled? || current_user&.has_permission?(AuthorizationBoundary::WRITE_PERMISSION)
  end

  def can_delete_boundary? = can_bulk_delete?

  # #1249 — the boundary page's Back Matter section: shown to someone who may
  # read it, editable by someone who may write it, both on THIS boundary. The
  # same keys Api::V1::BoundaryBackMatterResourcesController and the web
  # BackMatterResourcesController enforce.
  def can_read_boundary_back_matter?(boundary)
    return true unless SparcConfig.any_auth_enabled?
    return false unless current_user

    AuthorizationBoundary::BACK_MATTER_READ_PERMISSIONS.all? do |key|
      current_user.has_permission?(key, authorization_boundary_id: boundary.id)
    end
  end

  def can_write_boundary_back_matter?(boundary)
    !SparcConfig.any_auth_enabled? ||
      current_user&.has_permission?(AuthorizationBoundary::BACK_MATTER_WRITE_PERMISSION, authorization_boundary_id: boundary.id)
  end
end
