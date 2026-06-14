# REST API for Control Catalog management.
#
# All endpoints require Bearer token authentication.
# Write operations (create, update, destroy) are admin-only.
# Read operations are available to all authenticated users.
#
# GET    /api/v1/control_catalogs          — list (filterable)
# GET    /api/v1/control_catalogs/:id      — show
# POST   /api/v1/control_catalogs          — create (admin)
# PATCH  /api/v1/control_catalogs/:id      — update (admin)
# DELETE /api/v1/control_catalogs/:id      — delete (admin, hard-delete)
#
# NIST 800-53 Controls:
#   AC-3 Access Enforcement (Bearer token auth, admin gates)
#   AC-6 Least Privilege (admin-only write access)
#   AU-12 Audit Record Generation (mutations logged via audit_log)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
#
class Api::V1::ControlCatalogsController < Api::V1::BaseController
  include DocumentApprovalApi
  # #575 Path D — authorize BEFORE finding so non-admin / unpermissioned
  # callers get 403 (not 404 leaking existence info), and accept either
  # the admin flag or an explicit `catalogs.write` permission so roles
  # like policy_manager can manage catalogs without instance-admin.
  before_action :authorize_catalogs_write!, only: [ :create, :update, :destroy, :submit_for_review ]
  before_action :set_catalog, only: [ :show, :update, :destroy, :submit_for_review, :approve, :reject ]

  # GET /api/v1/control_catalogs
  def index
    scope = ControlCatalog.order(created_at: :desc)
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where("name ILIKE ?", "%#{params[:name]}%") if params[:name].present?
    scope = scope.where(lifecycle_status: params[:lifecycle_status]) if params[:lifecycle_status].present?

    result = paginate(scope)
    render json: {
      data: result[:data].map { |c| serialize_catalog(c) },
      meta: result[:meta]
    }
  end

  # GET /api/v1/control_catalogs/:id
  def show
    render json: { data: serialize_catalog(@catalog, detailed: true) }
  end

  # POST /api/v1/control_catalogs
  def create
    catalog = ControlCatalog.new(catalog_params)
    catalog.save!

    audit_log("control_catalog_created", subject: catalog, metadata: { name: catalog.name })
    render json: { data: serialize_catalog(catalog) }, status: :created
  end

  # PATCH /api/v1/control_catalogs/:id
  def update
    @catalog.update!(catalog_params)

    audit_log("control_catalog_updated", subject: @catalog, metadata: { name: @catalog.name })
    # #555 — return the detailed shape so callers can read-after-write.
    render json: { data: serialize_catalog(@catalog, detailed: true) }
  end

  # DELETE /api/v1/control_catalogs/:id
  def destroy
    name = @catalog.name
    @catalog.destroy!

    audit_log("control_catalog_deleted", subject: @catalog, metadata: { name: name })
    render json: { data: { id: @catalog.id, deleted: true } }
  rescue ActiveRecord::RecordNotDestroyed => e
    render json: { error: "Cannot delete catalog with dependencies: #{e.message}" }, status: :unprocessable_entity
  end

  private

  # #575 Path D — admins always pass; everyone else needs the
  # `catalogs.write` role permission. Mirrors the pattern in
  # DocumentBaseController#authorize_document_write! but for an
  # instance-scoped (non-boundary) resource.
  def authorize_catalogs_write!
    return if current_user&.admin?
    return if current_user&.has_permission?("catalogs.write")

    render json: { error: "Forbidden" }, status: :forbidden
  end

  # #566 — accept either numeric id or slug as the URL segment. The
  # Create response returns both, and a caller that builds a follow-up
  # URL from `id` shouldn't 404 just because they didn't notice that
  # show/update/destroy historically only matched on slug.
  # #630 — DocumentApprovalApi hook.
  def approval_document = @catalog

  def set_catalog
    id_or_slug = params[:id].to_s
    @catalog = if id_or_slug.match?(/\A\d+\z/)
      ControlCatalog.find_by!(id: id_or_slug)
    else
      ControlCatalog.find_by!(slug: id_or_slug)
    end
  end

  def catalog_params
    params.require(:control_catalog).permit(
      :name, :description, :version, :source, :oscal_version, :lifecycle_status
    )
  end

  def serialize_catalog(catalog, detailed: false)
    data = {
      id: catalog.id,
      slug: catalog.slug,
      oscal_uuid: catalog.oscal_uuid,
      name: catalog.name,
      version: catalog.version,
      source: catalog.source,
      status: catalog.status,
      lifecycle_status: catalog.lifecycle_status,
      oscal_version: catalog.oscal_version,
      published: catalog.published,
      created_at: catalog.created_at.iso8601,
      updated_at: catalog.updated_at.iso8601
    }

    if detailed
      data[:description] = catalog.description
      data[:total_controls] = catalog.total_controls
      data[:families_count] = catalog.control_families.count
      data[:short_digest] = catalog.short_digest
    end

    append_oscal_fields(data, catalog, detailed: detailed)
  end
end
