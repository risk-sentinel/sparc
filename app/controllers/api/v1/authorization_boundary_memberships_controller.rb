# REST API for the legacy Authorization Boundary personnel roster (#875).
#
# These records were the one mutation SPARC offered exclusively through the UI:
# a boundary's roster could be built, corrected and torn down from the browser
# with no API equivalent, so nothing automated could provision personnel. The
# web controller and this one share the model, which owns role resolution and
# validation, so the two cannot drift on what a role means.
#
# All endpoints require Bearer token authentication and are scoped to the
# parent boundary. Read requires read access to that boundary; every mutation
# requires write.
#
# GET    /api/v1/authorization_boundaries/:id/memberships        — list
# GET    /api/v1/authorization_boundaries/:id/memberships/roles  — configured vocabulary
# GET    /api/v1/authorization_boundaries/:id/memberships/:id    — show
# POST   /api/v1/authorization_boundaries/:id/memberships        — create
# PATCH  /api/v1/authorization_boundaries/:id/memberships/:id    — update
# DELETE /api/v1/authorization_boundaries/:id/memberships/:id    — delete
#
# NIST 800-53 Controls:
#   AC-2 Account Management (roster membership lifecycle)
#   AC-3 Access Enforcement (boundary-scoped read/write gating)
#   AU-2 Audit Events (every mutation is audited)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class Api::V1::AuthorizationBoundaryMembershipsController < Api::V1::BaseController
  before_action :set_boundary
  before_action :authorize_boundary_read!, only: [ :index, :show, :roles ]
  before_action :authorize_boundary_write!, only: [ :create, :update, :destroy ]
  before_action :set_membership, only: [ :show, :update, :destroy ]

  # GET /api/v1/authorization_boundaries/:authorization_boundary_id/memberships
  def index
    scope = @boundary.authorization_boundary_memberships.order(:role, :user_name)
    scope = scope.where(role: AuthorizationBoundaryMembership.resolve_role(params[:role])) if params[:role].present?

    result = paginate(scope)
    render json: {
      data: result[:data].map { |m| serialize_membership(m) },
      meta: result[:meta]
    }
  end

  # GET /api/v1/authorization_boundaries/:authorization_boundary_id/memberships/roles
  #
  # #875 — the role vocabulary is configurable (SPARC_AUTH_BOUNDARY_ROLES), so a
  # client that hardcoded the seven built-ins would be wrong on a configured
  # instance. `available` is what this instance offers for a NEW assignment;
  # `acceptable` additionally includes the built-ins, which stay valid on
  # records that already hold them even when the offered list is narrowed.
  def roles
    render json: {
      data: {
        available: AuthorizationBoundaryMembership.role_options.map { |label, value|
          { value: value, label: label }
        },
        acceptable: AuthorizationBoundaryMembership.acceptable_roles
      }
    }
  end

  # GET /api/v1/authorization_boundaries/:authorization_boundary_id/memberships/:id
  def show
    render json: { data: serialize_membership(@membership) }
  end

  # POST /api/v1/authorization_boundaries/:authorization_boundary_id/memberships
  def create
    membership = @boundary.authorization_boundary_memberships.new(membership_params)
    membership.save!

    audit_log("api_authorization_boundary_membership_created", subject: membership,
              metadata: { authorization_boundary_id: @boundary.id,
                          user_name: membership.user_name, role: membership.role })
    render json: { data: serialize_membership(membership) }, status: :created
  end

  # PATCH /api/v1/authorization_boundaries/:authorization_boundary_id/memberships/:id
  def update
    @membership.update!(membership_params)

    audit_log("api_authorization_boundary_membership_updated", subject: @membership,
              metadata: { authorization_boundary_id: @boundary.id, role: @membership.role })
    render json: { data: serialize_membership(@membership) }
  end

  # DELETE /api/v1/authorization_boundaries/:authorization_boundary_id/memberships/:id
  def destroy
    name = @membership.user_name
    @membership.destroy!

    audit_log("api_authorization_boundary_membership_deleted", subject: @membership,
              metadata: { authorization_boundary_id: @boundary.id, user_name: name })
    render json: { data: { id: @membership.id, deleted: true } }
  end

  private

  # #574 — accept either numeric id or slug, matching the boundaries endpoint.
  def set_boundary
    id_or_slug = params[:authorization_boundary_id].to_s
    @boundary = if id_or_slug.match?(/\A\d+\z/)
      AuthorizationBoundary.find_by!(id: id_or_slug)
    else
      AuthorizationBoundary.find_by!(slug: id_or_slug)
    end
  end

  # Scoped to the parent boundary, so an id from another boundary 404s rather
  # than leaking or mutating a roster the caller was not authorized against.
  def set_membership
    @membership = @boundary.authorization_boundary_memberships.find(params[:id])
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

  # `role` is permitted and left to the model, which resolves it (case,
  # punctuation, known labels and abbreviations) and validates it against the
  # configured vocabulary — the same path the web controller takes, so the API
  # and the UI cannot disagree about what is acceptable.
  def membership_params
    params.require(:authorization_boundary_membership).permit(:user_name, :user_email, :role)
  end

  def serialize_membership(m)
    {
      id: m.id,
      user_name: m.user_name,
      user_email: m.user_email,
      user_id: m.user_id,
      role: m.role,
      role_label: m.role_label,
      authorization_boundary_id: m.authorization_boundary_id,
      created_at: m.created_at.iso8601,
      updated_at: m.updated_at.iso8601
    }
  end
end
