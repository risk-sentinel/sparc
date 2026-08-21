# REST API for Component Definition (CDEF) Document management.
#
# All endpoints require Bearer token authentication.
#
# #1032 — writes require `cdef.write`, matching the web controller. They were
# open to any authenticated user until then, so the permission existed, the web
# enforced it, and the API did not: `cdef.write` could be routed around by using
# it. CDEF was the only API document controller with ungated writes.
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
  include ReconciliationGate

  include DocumentApprovalApi
  include FieldImportable
  # #1031 — file ingest; a CDEF is normally authored elsewhere.
  include DocumentFileIngestApi
  before_action :set_cdef, only: [ :show, :update, :destroy, :bulk_apply_converter_preview, :bulk_apply_converter_confirm, :source_from_profile, :submit_for_review, :approve, :reject, :import_fields_preview, :import_fields_confirm, :update_scope, :export ]
  # #629 — bulk delete is admin-only.
  before_action :authorize_admin!, only: [ :bulk_destroy ]
  # #1032 — every write gated on `cdef.write`, the same permission and the same
  # action list as the web controller, and the same shape as every sibling API
  # controller (SSP/SAR/SAP/POA&M `authorize_document_write!`, Profile
  # `authorize_profiles_write!`, catalogs `authorize_catalogs_write!`).
  #
  # Not listed here, and deliberately: `bulk_destroy` is admin-only, the
  # field-import pair is gated on `converters.write` (#499), and `approve` /
  # `reject` carry their own authority check inside DocumentApprovalService —
  # adding `cdef.write` to those would change who can approve, which is a
  # different decision.
  before_action :authorize_cdef_write!, only: [ :create, :update, :destroy, :import,
                                                :source_from_profile, :submit_for_review,
                                                :update_scope ]
  # #716 — field import is a bulk mutation; gate it like bulk-apply (converters.write).
  before_action :authorize_bulk_apply!, only: [ :import_fields_preview, :import_fields_confirm ]

  # #716 — FieldImportable hook (CDEF loads into @cdef).
  def field_import_document = @cdef

  # #1031 — DocumentFileIngestApi hook.
  def ingest_type_key = :cdef

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

    # #887 §5 — free-text search and the browse facets, shared with the web
    # index. Before this, `?q=` here matched name/description only while the
    # UI also matched regions, control ids and capabilities, and the facets
    # did not exist on the API at all.
    query = CdefBrowseQuery.new(params, scope: scope)
    result = paginate(query.documents)

    # Summarise only the page, the way the card view does.
    summaries = CdefComponent.summary_for(result[:data].map(&:id))

    render json: {
      data: result[:data].map { |c| serialize_cdef(c, summary: summaries[c.id]) },
      meta: result[:meta].merge(facets: query.applied_facets)
    }
  end

  # GET /api/v1/cdef_documents/:id
  def show
    render json: {
      data: serialize_cdef(@cdef, detailed: true,
                                  summary: CdefComponent.summary_for([ @cdef.id ])[@cdef.id])
    }
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
    finalize_unprocessed_create(cdef)   # #618 — no file to parse ⇒ don't hang in `pending`

    audit_log("cdef_document_created", subject: cdef, metadata: { name: cdef.name })
    render json: { data: serialize_cdef(cdef) }, status: :created
  rescue CdefMutationService::ValidationError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # PATCH /api/v1/cdef_documents/:id
  def update
    # #911 layer 2 — OSCAL requires `control-implementation/@source`: a
    # component claims to implement controls FROM something. Refuse the edit
    # until it says what. Declaring the profile is itself permitted.
    return unless enforce_reconciliation!(@cdef, cdef_params)

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

  # PATCH /api/v1/cdef_documents/:id/scope
  #
  # #929 — parity with the web `update_scope`, so the UI stays a thin client
  # over the API rather than the only place a CDEF's scope can be re-pointed.
  # Body: { "scope": "global" | "boundary", "authorization_boundary_id": N }
  def update_scope
    # #1032 — the inline `cdef.write` check that used to live here is now the
    # shared before_action above. It was correct, but it was one gate plus a
    # special case, which is how the two drift.
    CdefScopeService.apply(@cdef,
      scope: params[:scope],
      authorization_boundary_id: params[:authorization_boundary_id],
      organization_id: current_user&.organizations&.first&.id)

    audit_log("cdef_document_scope_updated", subject: @cdef,
      metadata: { name: @cdef.name, scope: params[:scope].to_s,
                  authorization_boundary_id: CdefScopeService.current_boundary_id(@cdef) })
    render json: { data: serialize_cdef(@cdef, detailed: true) }
  rescue ArgumentError => e
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

  # POST /api/v1/cdef_documents/:id/source_from_profile
  #
  # #628 — give a metadata-only CDEF shell a control basis instead of a dead
  # end. #982 renamed it: OSCAL reaches a profile from a component-definition
  # only through `control-implementation/@source`, never an import. The old
  # `populate_from_profile` path still routes here (deprecated, removal
  # v1.18.0) so integrators are not broken by the correction.
  def source_from_profile
    profile = find_published_profile(params[:source_profile_id])
    return render(json: { error: "Published profile not found" }, status: :not_found) unless profile

    CdefFromProfileService.new(profile).populate(@cdef)

    audit_log("cdef_control_implementation_sourced_from_profile", subject: @cdef,
              metadata: { name: @cdef.name, source_profile_id: profile.id, source_profile_name: profile.name })
    render json: { data: serialize_cdef(@cdef, detailed: true) }
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue CdefMutationService::ValidationError => e
    render json: { error: "OSCAL validation failed: #{e.message.truncate(200)}" }, status: :unprocessable_entity
  end

  # DELETE /api/v1/cdef_documents/bulk
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
      }, status: :unprocessable_entity
    end

    result = BulkDestroyService.new(
      model_class: CdefDocument, ids: payload.ids,
      user: current_user, ip_address: request.remote_ip
    ).call
    render json: {
      data: { deleted: result.deleted, blocked: result.blocked, missing: result.missing },
      meta: { deleted: result.deleted.size, blocked: result.blocked.size, missing: result.missing.size }
    }
  end

  # DELETE /api/v1/cdef_documents/:id
  def destroy
    @cdef.soft_delete!

    audit_log("cdef_document_deleted", subject: @cdef, metadata: { name: @cdef.name })
    render json: { data: { id: @cdef.id, slug: @cdef.slug, deleted: true } }
  end

  # GET /api/v1/cdef_documents/:id/export
  #
  # #1026 — the field-import endpoints WRITE control fields (notes,
  # implementation_narrative, implementation_status, control_origin,
  # responsible_roles, set_parameters, status_override) and until this action
  # existed nothing in the API read them back: `show` reports `controls_count`
  # and carries no `controls`. The write's own `applied` count was the only
  # evidence a caller had, which is the shape #994 was filed for.
  #
  # Authenticated-user read, matching `show` and the web `download_json` — a
  # CDEF is instance-global, not boundary-scoped, so there is no boundary to
  # scope this to. `CdefDocument#to_json_data` already emitted `controls:` with
  # each control's fields; only the route was missing.
  def export
    render json: JSON.parse(JsonExportService.export_cdef(@cdef))
  end

  private

  def set_cdef
    @cdef = CdefDocument.find_by!(slug: params[:id])
  end

  # #630 — DocumentApprovalApi hook.
  def approval_document = @cdef

  # #628 — resolve a published profile by slug or numeric id. Only published
  # profiles with a resolved catalog are a valid control basis.
  def find_published_profile(id_or_slug)
    id_or_slug = id_or_slug.to_s
    scope = ProfileDocument.where(lifecycle_status: "published")
    profile = if id_or_slug.match?(/\A\d+\z/)
      scope.find_by(id: id_or_slug)
    else
      scope.find_by(slug: id_or_slug)
    end
    profile
  end

  # #1032 — the same helper name and body as the web controller's, so the two
  # gates cannot drift apart.
  def authorize_cdef_write!
    authorize_permission!("cdef.write")
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
    permit_strictly(:cdef_document,
      :name, :description, :cdef_type, :cdef_version, :benchmark_id,
      :oscal_version, :lifecycle_status, :file_type,
      # #944 — the component's own OSCAL fields. The exporter hardcoded these,
      # so an integrator could create a CDEF over the API and still had no way
      # to say what kind of component it described.
      :component_type, :component_title, :component_description,
      :control_implementation_source, :control_implementation_description
    )
  end

  def serialize_cdef(cdef, detailed: false, summary: nil)
    data = {
      id: cdef.id,
      slug: cdef.slug,
      uuid: cdef.uuid,
      name: cdef.name,
      status: cdef.status,
      lifecycle_status: cdef.lifecycle_status,
      # #627/#628 — content-completeness is distinct from the parse `status`.
      # A metadata-only create is `status: completed` yet content-incomplete.
      content_complete: cdef.content_complete?,
      content_completeness_gaps: cdef.content_completeness_gaps,
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

      # #944 — the component's own OSCAL fields, reported so a consumer can see
      # what will be exported rather than discovering the hardcoded defaults
      # from the artifact. DETAIL only: five authoring fields on every index row
      # is payload nobody asked for, and `description` already sets that
      # precedent.
      data[:component_type] = cdef.component_type
      data[:component_title] = cdef.component_title
      data[:component_description] = cdef.component_description
      data[:control_implementation_source] = cdef.control_implementation_source
      data[:control_implementation_description] = cdef.control_implementation_description

      # #911 — lineage and unmapped STIG rules in ONE object, carrying the
      # remedy. Same shape whether advisory or the body of a 422 refusal, so an
      # integrator writes one handler; `blocking` is what tells them apart.
      reconciliation = cdef.reconciliation
      data[:reconciliation] = reconciliation if reconciliation
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

    # #887 — the enriched shape the card view renders. It is derived from the
    # component index rather than computed in the view, so an API consumer sees
    # the same services, partitions, capabilities and check coverage a user
    # does. `components` is a real state when nothing has been indexed yet, so
    # the empty summary is returned rather than omitting the key.
    data[:components] = serialize_component_summary(summary || CdefComponent.empty_summary)

    # The detailed shape lists the components themselves. On the index that
    # would be a row-count multiplier for no benefit — the roll-up is what a
    # list needs.
    if detailed
      data[:component_details] = cdef.cdef_components
                                    .order(Arel.sql("component_type = 'service' DESC"), :title)
                                    .map { |c| serialize_component(c) }
    end

    append_oscal_fields(data, cdef, detailed: detailed)
  end

  def serialize_component_summary(summary)
    {
      count: summary[:component_count],
      service_count: summary[:service_count],
      service_titles: summary[:service_titles],
      description: summary[:primary_description],
      partitions: summary[:partitions].map do |p|
        { id: p, label: CdefComponent.partition_label(p) }
      end,
      # False means the services in this definition are NOT available in the
      # same places, so the unioned partition list overstates any one of them.
      partitions_uniform: summary[:partitions_uniform],
      region_count: summary[:region_count],
      availability: summary[:availability],
      lifecycle_stages: summary[:lifecycle_stages],
      capabilities: {
        declared: summary[:declared_capabilities],
        derived: summary[:derived_capabilities]
      },
      check_count: summary[:check_count],
      # Controls the upstream definition asserts itself, vs those SPARC mapped
      # in. Kept apart so a consumer can tell what the vendor claimed.
      control_counts: {
        native: summary[:native_control_count],
        enriched: summary[:enriched_control_count]
      },
      mapping_sources: summary[:mapping_sources]
    }
  end

  def serialize_component(component)
    {
      uuid: component.component_uuid,
      type: component.component_type,
      title: component.title,
      description: component.description,
      service_id: component.service_id,
      region_ids: component.region_ids,
      partitions: component.partitions.map do |p|
        { id: p, label: CdefComponent.partition_label(p) }
      end,
      availability: component.availability,
      lifecycle_stage: component.lifecycle_stage,
      capabilities: {
        declared: component.declared_capabilities,
        derived: component.derived_capabilities
      },
      has_checks: component.has_checks,
      check_ids: component.check_ids,
      control_ids: {
        native: component.native_control_ids,
        enriched: component.enriched_control_ids
      },
      mapping_sources: component.mapping_sources
    }
  end
end
