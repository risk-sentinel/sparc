# frozen_string_literal: true

# Authorization concern for ApplicationController.
#
# Provides role-checking helpers and an admin gate. When auth is not
# enabled, all authorization checks pass (backward compatible).
module Authorization
  extend ActiveSupport::Concern

  class NotAuthorizedError < StandardError; end

  included do
    rescue_from NotAuthorizedError, with: :handle_not_authorized
  end

  # Require the current user to be an Instance Admin.
  def authorize_admin!
    return unless SparcConfig.any_auth_enabled?
    return if current_user&.admin?

    raise NotAuthorizedError, "Admin access required"
  end

  # Require the current user to have a specific role.
  #
  #   authorize_role!("isso")
  #   authorize_role!("isso", project_id: @project.id)
  def authorize_role!(role_name, project_id: nil)
    return unless SparcConfig.any_auth_enabled?
    return if current_user&.has_role?(role_name, project_id: project_id)

    raise NotAuthorizedError, "Role '#{role_name}' required"
  end

  # Require the current user to have a specific granular permission.
  #
  #   authorize_permission!("ssp.write")
  #   authorize_permission!("ssp.write", project_id: @project.id)
  def authorize_permission!(permission_key, project_id: nil)
    return unless SparcConfig.any_auth_enabled?
    return if current_user&.has_permission?(permission_key, project_id: project_id)

    raise NotAuthorizedError, "Permission '#{permission_key}' required"
  end

  private

  def handle_not_authorized(exception)
    Rails.logger.warn("[Authorization] Denied: #{exception.message} for user #{current_user&.id}")

    if request.format.json?
      render json: { error: "Forbidden" }, status: :forbidden
    else
      redirect_to root_path, error: "You are not authorized to perform this action."
    end
  end
end
