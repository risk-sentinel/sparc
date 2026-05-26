# REST API for Authorization Boundary management.
#
# All endpoints require Bearer token authentication.
# Non-admins see only boundaries they have roles on.
#
# GET    /api/v1/authorization_boundaries          — list
# GET    /api/v1/authorization_boundaries/:id      — show
# POST   /api/v1/authorization_boundaries          — create
# PATCH  /api/v1/authorization_boundaries/:id      — update
# DELETE /api/v1/authorization_boundaries/:id      — delete
#
class Api::V1::AuthorizationBoundariesController < Api::V1::BaseController
  before_action :set_boundary, only: [ :show, :update, :destroy ]
  before_action :authorize_boundary_read!, only: [ :show ]
  before_action :authorize_boundary_write!, only: [ :create, :update ]
  before_action :authorize_admin!, only: [ :destroy ]

  # GET /api/v1/authorization_boundaries
  def index
    scope = if current_user.admin?
      AuthorizationBoundary.all
    else
      current_user.authorization_boundaries.distinct
    end

    scope = scope.order(:name)
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where("name ILIKE ?", "%#{params[:name]}%") if params[:name].present?

    result = paginate(scope)
    render json: {
      data: result[:data].map { |ab| serialize_boundary(ab) },
      meta: result[:meta]
    }
  end

  # GET /api/v1/authorization_boundaries/:id
  def show
    render json: { data: serialize_boundary(@boundary, detailed: true) }
  end

  # POST /api/v1/authorization_boundaries
  def create
    boundary = AuthorizationBoundary.new(boundary_params)
    boundary.save!

    audit_log("api_authorization_boundary_created", subject: boundary, metadata: { name: boundary.name })
    render json: { data: serialize_boundary(boundary) }, status: :created
  end

  # PATCH /api/v1/authorization_boundaries/:id
  def update
    @boundary.update!(boundary_params)

    audit_log("api_authorization_boundary_updated", subject: @boundary, metadata: { name: @boundary.name })
    render json: { data: serialize_boundary(@boundary) }
  end

  # DELETE /api/v1/authorization_boundaries/:id
  def destroy
    name = @boundary.name
    @boundary.destroy!

    audit_log("api_authorization_boundary_deleted", subject: @boundary, metadata: { name: name })
    render json: { data: { id: @boundary.id, deleted: true } }
  end

  private

  # #574 — accept either numeric id or slug.
  def set_boundary
    id_or_slug = params[:id].to_s
    @boundary = if id_or_slug.match?(/\A\d+\z/)
      AuthorizationBoundary.find_by!(id: id_or_slug)
    else
      AuthorizationBoundary.find_by!(slug: id_or_slug)
    end
  end

  def authorize_boundary_read!
    return if current_user.admin?
    return if current_user.has_permission?("authorization_boundaries.read", authorization_boundary_id: @boundary.id)

    raise NotAuthorizedError, "Not authorized to view this authorization boundary"
  end

  def authorize_boundary_write!
    return if current_user.admin?
    return if current_user.has_permission?("authorization_boundaries.write")

    raise NotAuthorizedError, "Not authorized to modify authorization boundaries"
  end

  def boundary_params
    params.require(:authorization_boundary).permit(:name, :description, :status, :authorization_boundary_description)
  end

  def serialize_boundary(ab, detailed: false)
    data = {
      id: ab.id,
      slug: ab.slug,
      name: ab.name,
      description: ab.description,
      status: ab.status,
      created_at: ab.created_at.iso8601,
      updated_at: ab.updated_at.iso8601
    }

    if detailed
      summary = ab.artifact_summary
      data[:artifact_summary] = summary
      data[:organization] = ab.organization&.name
      data[:members_count] = ab.authorization_boundary_memberships.count
      data[:environments] = ab.boundaries.map { |b|
        { name: b.name, environment: b.environment, components: b.cdef_documents.count }
      }
    end

    data
  end
end
