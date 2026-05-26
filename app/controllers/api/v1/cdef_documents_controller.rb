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

    # Issue #466 — filter by provenance. source_type=aws_labs returns only
    # AWS-Labs-sourced CDEFs (the inventory); source_type=user_upload
    # excludes them.
    if params[:source_type].present?
      scope = scope.where("import_metadata->>'source_type' = ?", params[:source_type])
    end

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
    # #498 slice 1 — route the mutation through CdefMutationService so
    # the post-mutation OSCAL hash is validated against the NIST
    # component-definition schema before the transaction commits. A
    # mutation that would produce an invalid OSCAL document is
    # rejected with 422 instead of silently persisting.
    CdefMutationService.apply(@cdef) do |c|
      c.update!(cdef_params)
    end

    audit_log("cdef_document_updated", subject: @cdef, metadata: { name: @cdef.name })
    # #555 — return the detailed shape so callers can read-after-write.
    render json: { data: serialize_cdef(@cdef, detailed: true) }
  rescue CdefMutationService::ValidationError => e
    render json: { error: e.message }, status: :unprocessable_entity
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

    # Issue #466 — expose AWS Labs provenance on every row so API consumers
    # can distinguish ingested from user-authored CDEFs.
    if cdef.aws_labs_source?
      data[:source] = {
        type: "aws_labs",
        url: cdef.source_url,
        sha: cdef.import_metadata["source_sha"],
        oscal_version: cdef.import_metadata["source_oscal_version"],
        fetched_at: cdef.import_metadata["fetched_at"]
      }
    elsif cdef.cloned_from_id.present?
      data[:source] = { type: "cloned", cloned_from_id: cdef.cloned_from_id }
    end

    append_oscal_fields(data, cdef, detailed: detailed)
  end
end
