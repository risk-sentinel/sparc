# frozen_string_literal: true

# Authorization concern for ApplicationController.
#
# Provides role-checking helpers and an admin gate. When auth is not
# enabled, all authorization checks pass (backward compatible).
#
# NIST 800-53 Controls:
#   AC-2 Account Management (role assignment enforcement)
#   AC-3 Access Enforcement (authorize_permission! gates)
#   AC-5 Separation of Duties (29 distinct roles)
#   AC-6 Least Privilege (granular JSONB permission keys)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
module Authorization
  extend ActiveSupport::Concern

  class NotAuthorizedError < StandardError; end

  included do
    rescue_from NotAuthorizedError, with: :handle_not_authorized
  end

  # Require the current user to be an Instance Admin.
  #
  # #1044 — THE ONLY DEFINITION. Four API controllers (organizations,
  # service_accounts, roles, api_tokens) each carried a private copy that
  # SHADOWED this one, so editing the shared gate silently missed four of the
  # most sensitive endpoints in the app. That duplication is itself the bug, and
  # it has to go before an `instance.administer` permission can be added here —
  # otherwise the permission would open the gate on 21 controllers and not the
  # four that matter most, which is a half-open door.
  #
  # A controller that wants a more specific refusal overrides
  # `admin_required_message` rather than the method, so a future change to the
  # AUTHORITY check cannot be silently skipped by a controller that only wanted
  # different wording. That is exactly how the four copies came to exist.
  def authorize_admin!
    return unless SparcConfig.any_auth_enabled?
    return if current_user&.admin?

    raise NotAuthorizedError, admin_required_message
  end

  def admin_required_message = "Admin access required"

  # Require the current user to have a specific role.
  #
  #   authorize_role!("isso")
  #   authorize_role!("isso", authorization_boundary_id: @authorization_boundary.id)
  def authorize_role!(role_name, authorization_boundary_id: nil)
    return unless SparcConfig.any_auth_enabled?
    return if current_user&.has_role?(role_name, authorization_boundary_id: authorization_boundary_id)

    raise NotAuthorizedError, "Role '#{role_name}' required"
  end

  # Require the current user to have a specific granular permission.
  #
  #   authorize_permission!("ssp.write")
  #   authorize_permission!("ssp.write", authorization_boundary_id: @authorization_boundary.id)
  def authorize_permission!(permission_key, authorization_boundary_id: nil)
    return unless SparcConfig.any_auth_enabled?
    return if current_user&.has_permission?(permission_key, authorization_boundary_id: authorization_boundary_id)

    raise NotAuthorizedError, "Permission '#{permission_key}' required"
  end

  private

  def handle_not_authorized(exception)
    Rails.logger.warn("[Authorization] Denied: #{exception.message} for user #{current_user&.id}")

    audit_log("authorization_failure",
      metadata: { reason: exception.message, path: request.fullpath, method: request.method })

    if request.format.json?
      render json: { error: "Forbidden" }, status: :forbidden
    else
      redirect_to root_path, error: "You are not authorized to perform this action."
    end
  end
end
