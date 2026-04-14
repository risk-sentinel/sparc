# REST API for Profile Document management.
#
# All endpoints require Bearer token authentication.
# All CRUD operations are available to any authenticated user.
#
# GET    /api/v1/profile_documents          — list (filterable)
# GET    /api/v1/profile_documents/:id      — show
# POST   /api/v1/profile_documents          — create
# PATCH  /api/v1/profile_documents/:id      — update
# DELETE /api/v1/profile_documents/:id      — delete (soft-delete)
#
# NIST 800-53 Controls:
#   AC-3 Access Enforcement (Bearer token auth on all endpoints)
#   AC-6 Least Privilege (authenticated user access)
#   AU-12 Audit Record Generation (mutations logged via audit_log)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
#
class Api::V1::ProfileDocumentsController < Api::V1::BaseController
  before_action :set_profile, only: [ :show, :update, :destroy ]

  # GET /api/v1/profile_documents
  def index
    scope = ProfileDocument.order(created_at: :desc)
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where("name ILIKE ?", "%#{params[:name]}%") if params[:name].present?
    scope = scope.where(baseline_level: params[:baseline_level]) if params[:baseline_level].present?
    scope = scope.where(control_catalog_id: params[:control_catalog_id]) if params[:control_catalog_id].present?

    result = paginate(scope)
    render json: {
      data: result[:data].map { |p| serialize_profile(p) },
      meta: result[:meta]
    }
  end

  # GET /api/v1/profile_documents/:id
  def show
    render json: { data: serialize_profile(@profile, detailed: true) }
  end

  # POST /api/v1/profile_documents
  def create
    profile = ProfileDocument.new(profile_params)
    profile.save!

    audit_log("profile_document_created", subject: profile, metadata: { name: profile.name })
    render json: { data: serialize_profile(profile) }, status: :created
  end

  # PATCH /api/v1/profile_documents/:id
  def update
    @profile.update!(profile_params)

    audit_log("profile_document_updated", subject: @profile, metadata: { name: @profile.name })
    render json: { data: serialize_profile(@profile) }
  end

  # DELETE /api/v1/profile_documents/:id
  def destroy
    @profile.soft_delete!

    audit_log("profile_document_deleted", subject: @profile, metadata: { name: @profile.name })
    render json: { data: { id: @profile.id, slug: @profile.slug, deleted: true } }
  end

  private

  def set_profile
    @profile = ProfileDocument.find_by!(slug: params[:id])
  end

  def profile_params
    params.require(:profile_document).permit(
      :name, :description, :baseline_level, :profile_version,
      :oscal_version, :control_catalog_id, :lifecycle_status, :file_type
    )
  end

  def serialize_profile(profile, detailed: false)
    data = {
      id: profile.id,
      slug: profile.slug,
      uuid: profile.uuid,
      name: profile.name,
      status: profile.status,
      lifecycle_status: profile.lifecycle_status,
      file_type: profile.file_type,
      baseline_level: profile.baseline_level,
      profile_version: profile.profile_version,
      oscal_version: profile.oscal_version,
      created_at: profile.created_at.iso8601,
      updated_at: profile.updated_at.iso8601
    }

    if detailed
      data[:description] = profile.description
      data[:control_catalog_id] = profile.control_catalog_id
      data[:catalog_name] = profile.control_catalog&.name
      data[:controls_count] = profile.profile_controls.count
    end

    append_oscal_fields(data, profile, detailed: detailed)
  end
end
