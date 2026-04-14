# REST API for Component Definition (CDEF) Document management.
#
# All endpoints require Bearer token authentication.
# All CRUD operations are available to any authenticated user.
#
# GET    /api/v1/cdef_documents          — list (filterable)
# GET    /api/v1/cdef_documents/:id      — show
# POST   /api/v1/cdef_documents          — create
# PATCH  /api/v1/cdef_documents/:id      — update
# DELETE /api/v1/cdef_documents/:id      — delete (soft-delete)
#
# NIST 800-53 Controls:
#   AC-3 Access Enforcement (Bearer token auth on all endpoints)
#   AC-6 Least Privilege (authenticated user access)
#   AU-12 Audit Record Generation (mutations logged via audit_log)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
#
class Api::V1::CdefDocumentsController < Api::V1::BaseController
  before_action :set_cdef, only: [ :show, :update, :destroy ]

  # GET /api/v1/cdef_documents
  def index
    scope = CdefDocument.order(created_at: :desc)
    scope = scope.where(status: params[:status]) if params[:status].present?
    scope = scope.where("name ILIKE ?", "%#{params[:name]}%") if params[:name].present?
    scope = scope.where(cdef_type: params[:cdef_type]) if params[:cdef_type].present?

    result = paginate(scope)
    render json: {
      data: result[:data].map { |c| serialize_cdef(c) },
      meta: result[:meta]
    }
  end

  # GET /api/v1/cdef_documents/:id
  def show
    render json: { data: serialize_cdef(@cdef, detailed: true) }
  end

  # POST /api/v1/cdef_documents
  def create
    cdef = CdefDocument.new(cdef_params)
    cdef.save!

    audit_log("cdef_document_created", subject: cdef, metadata: { name: cdef.name })
    render json: { data: serialize_cdef(cdef) }, status: :created
  end

  # PATCH /api/v1/cdef_documents/:id
  def update
    @cdef.update!(cdef_params)

    audit_log("cdef_document_updated", subject: @cdef, metadata: { name: @cdef.name })
    render json: { data: serialize_cdef(@cdef) }
  end

  # DELETE /api/v1/cdef_documents/:id
  def destroy
    @cdef.soft_delete!

    audit_log("cdef_document_deleted", subject: @cdef, metadata: { name: @cdef.name })
    render json: { data: { id: @cdef.id, slug: @cdef.slug, deleted: true } }
  end

  private

  def set_cdef
    @cdef = CdefDocument.find_by!(slug: params[:id])
  end

  def cdef_params
    params.require(:cdef_document).permit(
      :name, :description, :cdef_type, :cdef_version, :benchmark_id,
      :oscal_version, :lifecycle_status, :file_type
    )
  end

  def serialize_cdef(cdef, detailed: false)
    data = {
      id: cdef.id,
      slug: cdef.slug,
      uuid: cdef.uuid,
      name: cdef.name,
      status: cdef.status,
      lifecycle_status: cdef.lifecycle_status,
      file_type: cdef.file_type,
      cdef_type: cdef.cdef_type,
      cdef_version: cdef.cdef_version,
      benchmark_id: cdef.benchmark_id,
      created_at: cdef.created_at.iso8601,
      updated_at: cdef.updated_at.iso8601
    }

    if detailed
      data[:description] = cdef.description
      data[:oscal_version] = cdef.oscal_version
      data[:controls_count] = cdef.cdef_controls.count
    end

    append_oscal_fields(data, cdef, detailed: detailed)
  end
end
