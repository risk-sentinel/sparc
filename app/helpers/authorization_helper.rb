# frozen_string_literal: true

module AuthorizationHelper
  # Check if the current user can perform write operations on catalogs.
  # Returns true when:
  #   1. Auth is disabled (backward compatible — show buttons to everyone)
  #   2. User is an Instance Admin
  #   3. User has the catalogs.write permission
  def can_write_catalogs?
    !SparcConfig.any_auth_enabled? || current_user&.admin? || current_user&.has_permission?("catalogs.write")
  end

  # Check if the current user can perform write operations on control mappings.
  def can_write_mappings?
    !SparcConfig.any_auth_enabled? || current_user&.admin? || current_user&.has_permission?("mappings.write")
  end
end
