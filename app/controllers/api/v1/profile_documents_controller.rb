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
  include ReconciliationGate

  # #575 Path D — admin OR `profiles.write` permission required for
  # any mutation. Was previously open to any authenticated user (no
  # gate at all). Run authorize BEFORE set_profile so a non-admin
  # without the permission gets 403, not 404 leaking existence.
  include DocumentApprovalApi
  before_action :authorize_profiles_write!, only: [ :create, :update, :destroy, :submit_for_review, :update_controls ]
  before_action :set_profile, only: [ :show, :update, :destroy, :submit_for_review, :approve, :reject, :baseline_review, :update_controls ]

  # GET /api/v1/profile_documents
  def index
    scope = ProfileDocument.order(created_at: :desc)
    # Not a facet on the index screen — free-text search covers it there — but
    # this endpoint has always accepted it, so it stays.
    scope = scope.where("name ILIKE ?", "%#{params[:name]}%") if params[:name].present?

    # #908 — status, baseline_level and control_catalog_id (plus the new
    # oscal_version / profile_version / lifecycle_status / uploaded_by /
    # created-range facets) come from ProfileBrowseQuery, the same object the
    # index screen uses.
    scope = ProfileBrowseQuery.new(params, scope: scope).records

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

  # GET /api/v1/profile_documents/:id/baseline_review
  # #633 — selected vs expected controls + ODP customization for reviewer sign-off.
  def baseline_review
    render json: { data: BaselineReviewService.new(@profile).review.to_h }
  end

  # PUT /api/v1/profile_documents/:id/controls
  # #757 — select/deselect baseline controls from the linked catalog (the API
  # equivalent of the UI baseline builder). Body: { control_ids: ["AC-1", ...] }.
  def update_controls
    result = ProfileControlSelectionService.new(@profile).update(params[:control_ids])
    audit_log("profile_controls_bulk_updated", subject: @profile,
              metadata: { added: result.added, removed: result.removed })
    render json: { data: { added: result.added, removed: result.removed,
                           controls_count: @profile.profile_controls.count } }
  rescue ProfileControlSelectionService::SelectionError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/profile_documents
  def create
    profile = ProfileDocument.new(profile_params)
    profile.save!
    finalize_unprocessed_create(profile)   # #618 — no file to parse ⇒ don't hang in `pending`

    audit_log("profile_document_created", subject: profile, metadata: { name: profile.name })
    render json: { data: serialize_profile(profile) }, status: :created
  end

  # PATCH /api/v1/profile_documents/:id
  def update
    # #911 layer 2 — a profile is the ROOT of the lineage chain, so an
    # unresolved one is the worst case: every SSP, SAP and SAR beneath it
    # inherits the break. Declaring the catalog is itself permitted.
    return unless enforce_reconciliation!(@profile, profile_params)

    # #928 — the web refuses to repoint a PUBLISHED profile at a different
    # catalog; this surface permitted it silently. `profile_params` has always
    # included `control_catalog_id`, so the API was the way around a rule the
    # UI enforces — the surface drift #919 exists to stop. Setting a catalog
    # that is missing stays allowed here too, for the same legacy-document
    # reason. (NIST CM-3, CA-5)
    if @profile.rebaselining_published?(profile_params)
      render json: { error: "This profile is published and its baseline is fixed. " \
                            "Copy it to point at a different catalog." },
             status: :unprocessable_entity
      return
    end

    @profile.update!(profile_params)

    audit_log("profile_document_updated", subject: @profile, metadata: { name: @profile.name })
    # #555 — return the detailed shape so callers can read-after-write.
    render json: { data: serialize_profile(@profile, detailed: true) }
  end

  # DELETE /api/v1/profile_documents/:id
  def destroy
    @profile.soft_delete!

    audit_log("profile_document_deleted", subject: @profile, metadata: { name: @profile.name })
    render json: { data: { id: @profile.id, slug: @profile.slug, deleted: true } }
  end

  private

  # #575 Path D — admin shortcut + `profiles.write` permission gate.
  def authorize_profiles_write!
    return if current_user&.admin?
    return if current_user&.has_permission?("profiles.write")

    render json: { error: "Forbidden" }, status: :forbidden
  end

  # #630 — DocumentApprovalApi hook.
  def approval_document = @profile

  # #574 — accept either numeric id or slug.
  def set_profile
    id_or_slug = params[:id].to_s
    @profile = if id_or_slug.match?(/\A\d+\z/)
      ProfileDocument.find_by!(id: id_or_slug)
    else
      ProfileDocument.find_by!(slug: id_or_slug)
    end
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
      # #627 — content-completeness is distinct from the parse `status`.
      content_complete: profile.content_complete?,
      content_completeness_gaps: profile.content_completeness_gaps,
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
      # #757 — the selected baseline control ids, so consumers can see/verify
      # the selection and drive the control-selection API (PUT .../controls).
      data[:control_ids] = profile.profile_controls.order(:row_order).pluck(:control_id)
    end

    append_oscal_fields(data, profile, detailed: detailed)
  end
end
