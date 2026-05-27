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
  before_action :set_cdef, only: [ :show, :update, :destroy, :bulk_apply_converter_preview, :bulk_apply_converter_confirm ]

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
    # #498 slice 2 — route through CdefMutationService for post-save
    # OSCAL validation. Empty-CDEF creates skip validation legitimately
    # (the service handles that), so a metadata-only create still works.
    CdefMutationService.apply(cdef) do |c|
      c.save!
    end

    audit_log("cdef_document_created", subject: cdef, metadata: { name: cdef.name })
    render json: { data: serialize_cdef(cdef) }, status: :created
  rescue CdefMutationService::ValidationError => e
    render json: { error: e.message }, status: :unprocessable_entity
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

  # POST /api/v1/cdef_documents/:id/bulk_apply_converter/preview
  # #499 slice 3 — return the changeset a Converter would apply to this
  # CDEF (no writes), plus a HMAC-signed token the confirm endpoint
  # (slice 4) will replay.
  def bulk_apply_converter_preview
    authorize_bulk_apply!

    converter = Converter.find_by(id: params[:converter_id]) ||
                Converter.find_by(uuid: params[:converter_id])
    return render(json: { error: "Converter not found" }, status: :not_found) unless converter

    if @cdef.aws_labs_source?
      return render(
        json: { error: "Cannot bulk-apply to an AWS-Labs-sourced CDEF — clone first" },
        status: :unprocessable_entity
      )
    end

    service = CdefBulkApplyService.new(
      cdef:                     @cdef,
      converter:                converter,
      target_rev:               params[:target_rev],
      source_ids:               params[:source_ids],
      only_missing_vs_baseline: ActiveModel::Type::Boolean.new.cast(params[:only_missing_vs_baseline])
    )

    result = service.preview

    audit_log_api("cdef_bulk_apply_converter_previewed", @cdef,
                  converter_id: converter.id, ready: result.stats[:ready])
    render json: {
      data: {
        cdef_id:        @cdef.id,
        cdef_slug:      @cdef.slug,
        converter_id:   converter.id,
        converter_uuid: converter.uuid,
        target_rev:     params[:target_rev],
        token:          result.token,
        stats:          result.stats,
        rows:           result.rows.map(&:to_h)
      }
    }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/cdef_documents/:id/bulk_apply_converter/confirm
  # #499 slice 4 — replay a preview token and apply ready rows via
  # CdefMutationService (transactional + OSCAL-validated).
  def bulk_apply_converter_confirm
    authorize_bulk_apply!

    if @cdef.aws_labs_source?
      return render(
        json: { error: "Cannot bulk-apply to an AWS-Labs-sourced CDEF — clone first" },
        status: :unprocessable_entity
      )
    end

    selected = params[:selected_target_ids].respond_to?(:to_unsafe_h) ? params[:selected_target_ids].to_unsafe_h : Hash(params[:selected_target_ids])

    result = CdefBulkApplyService.apply!(
      cdef:                @cdef,
      token:               params[:token].to_s,
      selected_target_ids: selected,
      user:                current_user
    )

    render json: { data: { cdef_id: @cdef.id, cdef_slug: @cdef.slug, **result } }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue CdefMutationService::ValidationError => e
    render json: { error: "OSCAL validation failed: #{e.message.truncate(200)}" }, status: :unprocessable_entity
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

  # #499 slice 3 — bulk-apply gated on converters.write (matches the
  # existing AWS Labs refresh authorization).
  def authorize_bulk_apply!
    return if current_user.admin?
    return if current_user.has_permission?("converters.write")

    raise NotAuthorizedError, "Not authorized to bulk-apply converters"
  end

  # #499 slice 4 — minimal AuditEvent wrapper for API context (the
  # controller's auditable concern lives in Auditable; mirror it here
  # for the API base controller which is ActionController::API).
  def audit_log_api(action, subject, metadata = {})
    AuditEvent.log(
      user:       current_user,
      action:     action,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      subject:    subject,
      metadata:   metadata
    )
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
