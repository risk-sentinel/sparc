# REST API for Authorization Boundary management.
#
# All endpoints require Bearer token authentication.
# The list holds only the boundaries the caller may read
# (AuthorizationBoundary.visible_to, #1248).
#
# GET    /api/v1/authorization_boundaries          — list (?sort=next_decision|-next_decision)
# GET    /api/v1/authorization_boundaries/:id      — show
# POST   /api/v1/authorization_boundaries          — create
# PATCH  /api/v1/authorization_boundaries/:id      — update
# DELETE /api/v1/authorization_boundaries/:id      — delete
#
class Api::V1::AuthorizationBoundariesController < Api::V1::BaseController
  # #1244 — the same rule as the web controller (AuthorizationBoundaryAccess).
  # Update now takes a boundary-scoped write grant; it accepted only an
  # instance-level one, refusing the boundary's own ISSO/ISSM (owner,
  # 2026-10-22). Create still needs an instance-level grant.
  include AuthorizationBoundaryAccess

  before_action :set_boundary, only: [ :show, :update, :destroy, :assign_organization ]
  before_action :authorize_boundary_read!, only: [ :show ]
  before_action :authorize_boundary_create!, only: [ :create ]
  before_action :authorize_boundary_write!, only: [ :update ]
  before_action :authorize_admin!, only: [ :destroy, :bulk_destroy ]
  # assign_organization intentionally omits the generic write gate: its
  # authorization is the org-admin matrix in BoundaryOrganizationAssigner (#770).

  # GET /api/v1/authorization_boundaries
  def index
    # #1248 — the boundaries this caller may see, from the one definition the
    # web list, sidebar and menus use (AuthorizationBoundary.visible_to), so a
    # boundary listed here always opens (show checks the same read grant). It
    # listed every boundary the caller held ANY role on, which disagreed with
    # show for a role without authorization_boundaries.read, and missed every
    # boundary for an instance-wide read grant (Global Viewer).
    scope = AuthorizationBoundary.visible_to(current_user)

    scope = scope.order(:name)
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where("name ILIKE ?", "%#{params[:name]}%") if params[:name].present?
    scope = scope.search_text(params[:q]) if params[:q].present? # #672 free-text search

    # #1248 — the list page's sort, from the same allow-list. An unknown value
    # is refused rather than ignored: a misspelt sort that answered in the
    # default order would look like it worked.
    if params[:sort].present?
      unless AuthorizationBoundary::SORTS.key?(params[:sort].to_s)
        return render json: { error: "Unknown sort", details: [ "sort must be one of: #{AuthorizationBoundary::SORTS.keys.join(', ')}" ] },
                      status: :unprocessable_content
      end

      scope = scope.sorted_by(params[:sort])
    end

    # #1178 — every row now carries its organization's uuid; preload it.
    result = paginate(scope.includes(:organization))
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

  # PATCH /api/v1/authorization_boundaries/:id/organization
  #
  # #770 bug 6 — assign, move, or clear the boundary's organization. Enforces
  # the org-admin authorization matrix via BoundaryOrganizationAssigner:
  # instance admin may assign/move/clear; a non-admin org_admin may attach an
  # UNASSIGNED boundary into their own org only. AC-3 / AC-6.
  #
  # Body: { organization_id: <id or null> }
  def assign_organization
    organization = params[:organization_id].present? ? Organization.find(params[:organization_id]) : nil

    BoundaryOrganizationAssigner.new(
      boundary: @boundary, organization: organization, actor: current_user
    ).call

    audit_log("api_authorization_boundary_org_assigned", subject: @boundary,
              metadata: { organization_id: organization&.id })
    render json: { data: serialize_boundary(@boundary) }
  rescue BoundaryOrganizationAssigner::MoveRequiresAdminError => e
    render json: { error: e.message }, status: :forbidden
  end

  # DELETE /api/v1/authorization_boundaries/bulk
  # #629 — admin-only bulk delete; honors the referential-integrity guard and
  # returns a per-id partial-success result.
  def bulk_destroy
    # #1018 — parse before deleting. `params[:ids]` used to be read straight
    # off the request, so a misspelled key deleted nothing and answered 200
    # with zeros: "nothing to do" and "I did not understand you" were the same
    # response, on an endpoint whose job is deletion.
    payload = BulkDestroyPayload.parse(params)
    unless payload.valid?
      return render json: {
        error: "The request body could not be parsed as a bulk delete. Nothing was changed.",
        details: payload.errors,
        expected: BulkDestroyPayload::EXPECTED
      }, status: :unprocessable_content
    end

    result = BulkDestroyService.new(
      model_class: AuthorizationBoundary, ids: payload.ids,
      user: current_user, ip_address: request.remote_ip
    ).call
    render json: {
      data: { deleted: result.deleted, blocked: result.blocked, missing: result.missing },
      meta: { deleted: result.deleted.size, blocked: result.blocked.size, missing: result.missing.size }
    }
  end

  # DELETE /api/v1/authorization_boundaries/:id
  def destroy
    name = @boundary.name
    # #629 — honor the referential-integrity guard (SSP/SAP/SAR/POA&M attached)
    # with a 422 instead of an unhandled RecordNotDestroyed 500.
    if @boundary.destroy
      audit_log("api_authorization_boundary_deleted", subject: @boundary, metadata: { name: name })
      render json: { data: { id: @boundary.id, deleted: true } }
    else
      audit_log("authorization_boundary_delete_blocked", subject: @boundary,
                metadata: { name: name, reason: @boundary.errors.full_messages.join(", ") })
      render json: { error: @boundary.errors.full_messages.join(", ") }, status: :unprocessable_content
    end
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

  def access_boundary = @boundary

  def boundary_params
    permit_strictly(:authorization_boundary, :name, :description, :status, :authorization_boundary_description,
                    # #1154 — decision dates (YYYY-MM-DD), stored in boundary_metadata.
                    :authorization_date, :next_decision_date)
  end

  def serialize_boundary(ab, detailed: false)
    data = {
      id: ab.id,
      slug: ab.slug,
      # #1180 — the boundary UUID is what the federation key grammar keys
      # objects on and what sparc-horizon joins against, yet this serializer
      # was the one place it was absent. Reaching it needed database access,
      # which most operators of a deployed instance do not have.
      uuid: ab.uuid,
      # #1178 — the organization link, on list AND detail, so a client can build
      # the organization -> boundary tree from the API alone (sparc-horizon).
      # Both are nil for a boundary not yet assigned to an organization.
      organization_id: ab.organization_id,
      organization_uuid: ab.organization&.uuid,
      name: ab.name,
      description: ab.description,
      status: ab.status,
      # #1154 — read back what the two date fields write. next_decision_date is
      # exported on the SSP as the SPARC-namespace prop `next-decision-date`.
      authorization_date: ab.authorization_date,
      next_decision_date: ab.next_decision_date,
      created_at: ab.created_at.iso8601,
      updated_at: ab.updated_at.iso8601
    }

    if detailed
      summary = ab.artifact_summary
      data[:artifact_summary] = summary
      # 1.18.0-rf #1293 — what each document list holds in this boundary for
      # the caller: the numbers the web navigation shows, from the same
      # definition (BoundaryNavCounts), so the two cannot disagree.
      data[:counts] = BoundaryNavCounts.for(ab, current_user)
      data[:organization] = ab.organization&.name
      # #770 bug 3 — count the full roster (canonical user_roles + legacy
      # memberships), matching what the boundary screen now shows. members_count
      # previously reflected only legacy memberships.
      # #1247 — distinct PEOPLE (AuthorizationBoundary#people_count), the list
      # page's Members figure. Roster rows counted a person with two roles twice.
      data[:members_count] = ab.people_count
      # #770 bug 5 — boundary-scoped evidence artifacts (OSCAL back-matter source).
      data[:evidences_count] = ab.evidences.count
      data[:environments] = ab.boundaries.map { |b|
        { name: b.name, environment: b.environment, components: b.cdef_documents.count }
      }
    end

    data
  end
end
