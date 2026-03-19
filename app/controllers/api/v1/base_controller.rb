# Base controller for all API v1 endpoints.
#
# Provides Bearer token authentication, RBAC authorization,
# JSON error handling, and pagination helpers.
#
class Api::V1::BaseController < ApplicationController
  include ApiAuthentication
  include Authorization
  include Pagy::Method

  protect_from_forgery with: :null_session
  skip_before_action :require_authentication
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
end
