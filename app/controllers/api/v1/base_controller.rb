# Base controller for all API v1 endpoints.
#
# Inherits from ActionController::API (not ApplicationController) to
# avoid CSRF, session, cookies, and other browser-specific middleware.
# Provides Bearer token authentication, RBAC authorization,
# JSON error handling, and pagination helpers.
#
class Api::V1::BaseController < ActionController::API
  include ApiAuthentication
  include Authorization
  include Pagy::Method

  before_action :authenticate_api_token!

  rescue_from ActiveRecord::RecordNotFound do |e|
    render json: { error: "Not found" }, status: :not_found
  end

  rescue_from ActiveRecord::RecordInvalid do |e|
    render json: { error: e.message, details: e.record&.errors&.full_messages }, status: :unprocessable_entity
  end

  rescue_from NotAuthorizedError do |e|
    render json: { error: "Forbidden" }, status: :forbidden
  end

  private

  def paginate(scope, items: 25)
    pagy, records = pagy(:offset, scope, limit: items)
    {
      data: records,
      meta: {
        page: pagy.page,
        pages: pagy.pages,
        count: pagy.count,
        items: pagy.limit
      }
    }
  end

  # Provide audit_log helper since we're not inheriting from ApplicationController.
  # Uses AuditEvent.log which handles polymorphic subject extraction.
  def audit_log(action, subject: nil, metadata: {})
    AuditEvent.log(
      action: action,
      user: current_user,
      subject: subject,
      metadata: metadata,
      ip_address: request.remote_ip
    )
  rescue => e
    Rails.logger.warn("Audit log failed: #{e.message}")
  end
end
