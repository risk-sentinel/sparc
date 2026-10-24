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

  # #1270 — mirrors ControlBackMatterLinksController#authorize_back_matter_write!
  # for a profile's controls, which have no boundary: an instance-level grant.
  def can_write_back_matter?
    !SparcConfig.any_auth_enabled? || current_user&.instance_administrator? || current_user&.has_permission?("back_matter.write")
  end

  # Check if the current user can perform write operations on converters.
  def can_write_converters?
    !SparcConfig.any_auth_enabled? || current_user&.instance_administrator? || current_user&.has_permission?("converters.write")
  end

  # #1243 — THE answer to "would authorize_admin! let this person in?": auth
  # disabled, or an instance administrator. Every link or control leading to
  # an administrator screen reads this, so it shows exactly when the screen
  # admits the user (the homepage's Organizations card, the Enterprise menu).
  def admin_access?
    !SparcConfig.any_auth_enabled? || current_user&.instance_administrator? || false
  end

  # #1243 — the Federation Peers screen is guarded by `back_matter.federate`
  # (FederationPeersController#require_admin), not by authorize_admin!, so its
  # links follow that key. An administrator holds every key.
  def can_federate?
    !SparcConfig.any_auth_enabled? || current_user&.has_permission?("back_matter.federate") || false
  end

  # #629 — bulk delete is instance-admin-only; mirror authorize_admin! so the
  # UI only renders the controls when the action would actually be allowed.
  def can_bulk_delete? = admin_access?

  # #1243 — CdefDocumentsController#authorize_cdef_write!: instance-level.
  # #1258 — may create a CDEF somewhere: instance-level cdef.write, or
  # cdef.write on any boundary (CdefWriteAccess).
  def can_write_cdefs?
    !SparcConfig.any_auth_enabled? || CdefWriteAccess.may_create?(current_user)
  end

  # #1243 — may this person create a document of a boundary-scoped type
  # anywhere? Create is authorized against the boundary the new document joins
  # (BoundaryScopedDocument#authorize_document_write!), so the write key on ANY
  # boundary, or instance-wide, is what makes "New" lead somewhere that works.
  # The key is the controller's own declaration.
  def can_create_boundary_document?(controller_class)
    !SparcConfig.any_auth_enabled? || current_user&.has_any_permission?(controller_class.bsd_write_key) || false
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

  # #1251 — `key` on this boundary (or instance-wide), the check
  # authorize_permission!(key, authorization_boundary_id:) makes. For a link or
  # button whose target controller enforces exactly that.
  def boundary_permission?(key, boundary)
    !SparcConfig.any_auth_enabled? ||
      current_user&.has_permission?(key, authorization_boundary_id: boundary.id) || false
  end

  # #1251 — LeveragedAuthorizationsController#authorize_leveraging_boundary!:
  # membership of the leveraging boundary, not a permission key (#919 memo).
  def can_manage_leveraged_authorizations?(boundary)
    return true unless SparcConfig.any_auth_enabled?
    return false unless current_user
    return true if current_user.instance_administrator?

    boundary.assigned_users.exists?(id: current_user.id)
  end

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
