# REST API for Control Mapping management.
#
# All endpoints require Bearer token authentication.
# Write operations (create, update, destroy) are admin-only.
# Read operations are available to all authenticated users.
#
# GET    /api/v1/control_mappings          — list (filterable)
# GET    /api/v1/control_mappings/:id      — show
# POST   /api/v1/control_mappings          — create (admin)
# PATCH  /api/v1/control_mappings/:id      — update (admin)
# DELETE /api/v1/control_mappings/:id      — delete (admin, hard-delete)
#
# NIST 800-53 Controls:
#   AC-3 Access Enforcement (Bearer token auth, admin gates)
#   AC-6 Least Privilege (admin-only write access)
#   AU-12 Audit Record Generation (mutations logged via audit_log)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
#
class Api::V1::ControlMappingsController < Api::V1::BaseController
  # #575 Path D — authorize BEFORE finding so non-admin / unpermissioned
  # callers get 403, not 404 leaking existence. Admin OR `mappings.write`
  # permission passes.
  before_action :authorize_mappings_write!, only: [ :create, :update, :destroy ]
  before_action :set_mapping, only: [ :show, :update, :destroy ]

  # GET /api/v1/control_mappings
  def index
    scope = ControlMapping.order(updated_at: :desc)
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where("name ILIKE ?", "%#{params[:name]}%") if params[:name].present?
    scope = scope.where(source_catalog_id: params[:source_catalog_id]) if params[:source_catalog_id].present?
    scope = scope.where(target_catalog_id: params[:target_catalog_id]) if params[:target_catalog_id].present?

    result = paginate(scope)
    render json: {
      data: result[:data].map { |m| serialize_mapping(m) },
      meta: result[:meta]
    }
  end

  # GET /api/v1/control_mappings/:id
  def show
    render json: { data: serialize_mapping(@mapping, detailed: true) }
  end

  # POST /api/v1/control_mappings
  def create
    mapping = ControlMapping.new(mapping_params)
    mapping.save!

    audit_log("control_mapping_created", subject: mapping, metadata: { name: mapping.name })
    render json: { data: serialize_mapping(mapping) }, status: :created
  end

  # PATCH /api/v1/control_mappings/:id
  def update
    @mapping.update!(mapping_params)

    audit_log("control_mapping_updated", subject: @mapping, metadata: { name: @mapping.name })
    # #555 — return the detailed shape so callers can read-after-write.
    render json: { data: serialize_mapping(@mapping, detailed: true) }
  end

  # DELETE /api/v1/control_mappings/:id
  def destroy
    name = @mapping.name
    @mapping.destroy!

    audit_log("control_mapping_deleted", subject: @mapping, metadata: { name: name })
    render json: { data: { id: @mapping.id, deleted: true } }
  end

  private

  # #575 Path D — admin shortcut + `mappings.write` permission gate.
  def authorize_mappings_write!
    return if current_user&.admin?
    return if current_user&.has_permission?("mappings.write")

    render json: { error: "Forbidden" }, status: :forbidden
  end

  # #566 — accept either numeric id or slug. See set_catalog above for
  # the rationale.
  def set_mapping
    id_or_slug = params[:id].to_s
    @mapping = if id_or_slug.match?(/\A\d+\z/)
      ControlMapping.find_by!(id: id_or_slug)
    else
      ControlMapping.find_by!(slug: id_or_slug)
    end
  end

  def mapping_params
    params.require(:control_mapping).permit(
      :name, :description, :status, :method_type, :matching_rationale,
      :mapping_version, :oscal_version, :source_catalog_id, :target_catalog_id
    )
  end

  def serialize_mapping(mapping, detailed: false)
    data = {
      id: mapping.id,
      slug: mapping.slug,
      uuid: mapping.uuid,
      name: mapping.name,
      status: mapping.status,
      method_type: mapping.method_type,
      matching_rationale: mapping.matching_rationale,
      mapping_version: mapping.mapping_version,
      oscal_version: mapping.oscal_version,
      created_at: mapping.created_at.iso8601,
      updated_at: mapping.updated_at.iso8601
    }

    if detailed
      data[:description] = mapping.description
      data[:source_catalog] = {
        id: mapping.source_catalog.id,
        name: mapping.source_catalog.name,
        slug: mapping.source_catalog.slug
      }
      data[:target_catalog] = {
        id: mapping.target_catalog.id,
        name: mapping.target_catalog.name,
        slug: mapping.target_catalog.slug
      }
      data[:entries_count] = mapping.entries_count
    end

    data
  end
end
