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

  # Resolve pagination size from request params (?items=N or ?per_page=N),
  # falling back to the per-endpoint default. Clamped to a hard ceiling to
  # prevent ?items=999999 from triggering a giant ActiveRecord query (#549).
  MAX_PAGINATION_LIMIT = 200

  def paginate(scope, items: 25)
    per_page = resolve_pagination_size(default: items)
    pagy, records = pagy(:offset, scope, limit: per_page)
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

  def resolve_pagination_size(default:)
    raw = params[:items].presence || params[:per_page].presence
    return default if raw.blank?

    n = raw.to_i
    return default if n <= 0

    [ n, MAX_PAGINATION_LIMIT ].min
  end

  # Shared OSCAL metadata and back-matter serialization for document APIs.
  # Call from serialize_document to append published, metadata_extra, and
  # back_matter_resources to any document response hash.
  def append_oscal_fields(data, doc, detailed: false)
    data[:published] = doc.try(:published)
    data[:back_matter_resources_count] = doc.respond_to?(:back_matter_resources) ? doc.back_matter_resources.count : 0

    if detailed
      data[:oscal_metadata] = doc.try(:metadata_extra) || {}
      if doc.respond_to?(:back_matter_resources)
        data[:back_matter_resources] = doc.back_matter_resources.order(:title).map do |r|
          serialize_back_matter_resource(r)
        end
      end
    end

    data
  end

  def serialize_back_matter_resource(resource, detailed: false)
    data = {
      id: resource.id,
      uuid: resource.uuid,
      title: resource.title,
      rel: resource.rel,
      media_type: resource.media_type,
      href: resource.href,
      source: resource.source,
      globally_available: resource.globally_available,
      organization_id: resource.organization_id,
      created_at: resource.created_at.iso8601,
      updated_at: resource.updated_at.iso8601
    }

    if detailed
      data[:description] = resource.description
      data[:resource_data] = resource.resource_data
      data[:evidence_id] = resource.evidence_id
      data[:resourceable_type] = resource.resourceable_type
      data[:resourceable_id] = resource.resourceable_id
      data[:linked_controls] = resource.control_back_matter_links.map do |link|
        { type: link.linkable_type, id: link.linkable_id }
      end
    end

    data
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
