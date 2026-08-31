# REST API for Security Assessment Plan (SAP) document management.
#
# All endpoints require Bearer token authentication.
# Non-admins see only SAP documents within their authorization boundaries.
#
# Standard CRUD:
#   GET    /api/v1/sap_documents          — list (paginated, filterable)
#   GET    /api/v1/sap_documents/:id      — show
#   POST   /api/v1/sap_documents          — create
#   PUT    /api/v1/sap_documents/:id      — update
#   DELETE /api/v1/sap_documents/:id      — soft-delete
#
# Generation:
#   POST   /api/v1/sap_documents/generate — build a POPULATED SAP from an SSP,
#                                           a profile, or a boundary (#844)
#
# NIST 800-53 Controls:
#   AC-3 Access Enforcement (boundary-scoped RBAC)
#   AU-12 Audit Record Generation (all mutations logged)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
#
class Api::V1::SapDocumentsController < Api::V1::DocumentBaseController
  include FieldImportable
  # #1031 — file ingest.
  include DocumentFileIngestApi

  # #716 — re-declare with the FULL list: re-registering an inherited before_action
  # updates its :only conditions rather than adding a second callback, so these
  # must include the parent's actions ([:show, :update, :destroy] / [:create,
  # :update, :destroy]) or they'd be dropped for SAP CRUD.
  before_action :set_document, only: [ :show, :update, :destroy, :export, :import_fields_preview, :import_fields_confirm ]
  before_action :authorize_document_read!, only: [ :show, :export ]
  before_action :authorize_document_write!,
                only: [ :create, :update, :destroy, :generate, :import,
                        :import_fields_preview, :import_fields_confirm ]

  # #716 — FieldImportable hook.
  def field_import_document = @document

  # #1031 — DocumentFileIngestApi hook.
  def ingest_type_key = :sap

  # POST /api/v1/sap_documents/generate
  #
  # #844 — generate a populated SAP from an SSP or a profile.
  #
  # The generator has existed since #28 and the UI has driven it since, but the
  # API exposed only CRUD. A 3PAO or any integrator working programmatically
  # could therefore create an EMPTY SAP shell and nothing else — the one
  # document in the authorization chain with no generation endpoint. The plan
  # is also not a once-per-assessment artifact: a boundary needs a fresh SAP
  # between assessments, which is a routine automated action rather than
  # something to click through a wizard.
  #
  # Sources, in order of precedence:
  #   1. an explicit ssp_document_id / profile_document_id
  #   2. the named boundary's own SSP, then its profile
  #
  # so `{"sap_document": {"authorization_boundary_id": 7}}` is a complete
  # request — which is the between-assessments case.
  def generate
    boundary = resolve_boundary
    ssp      = resolve_ssp(boundary)
    profile  = resolve_profile(boundary)

    # Fall back to the SSP's own boundary. Without this, generating by
    # ssp_document_id alone produced an ORPHAN SAP attached to nothing — it
    # would not appear in the boundary's document set and `boundary.sap_document`
    # would stay nil, so the plan existed but the boundary still looked like it
    # had none. Safe to derive rather than demand: resolve_ssp has already
    # restricted the SSP to one the caller can read.
    boundary ||= ssp&.authorization_boundary

    # The generator returns an empty control set when given neither, which
    # would persist a SAP with no controls and report success. An assessment
    # plan covering nothing is not a degraded result, it is a wrong one.
    if ssp.nil? && profile.nil?
      return render(json: {
        error: "No control basis. Supply ssp_document_id or profile_document_id, " \
               "or an authorization_boundary_id whose boundary has an SSP or a profile."
      }, status: :unprocessable_content)
    end

    # Rolled back when the result covers no controls. `filter_controls`
    # normalises CASE but not zero-padding, so `ac-2` does not match an SSP
    # control stored as `AC-02` — a plausible caller mistake that otherwise
    # persists an empty SAP and reports 201. An assessment plan covering
    # nothing is a wrong answer, not a small one, and it is worse than an error
    # because it looks like success.
    sap = ActiveRecord::Base.transaction do
      generated = SapGeneratorService.new(
        name: generate_params[:name].presence || default_sap_name(boundary, ssp),
        ssp_document: ssp,
        profile_document: profile,
        assessment_type: generate_params[:assessment_type].presence || "initial",
        assessment_start: generate_params[:assessment_start],
        assessment_end: generate_params[:assessment_end],
        description: generate_params[:description],
        selected_control_ids: Array(generate_params[:control_ids]).reject(&:blank?).presence,
        assessment_methods: generate_params[:assessment_methods]&.to_h,
        # #952 — passed in, not patched on afterwards: a SAP with no boundary
        # can no longer be saved at all.
        authorization_boundary: boundary
      ).generate

      raise ActiveRecord::Rollback if generated.sap_controls.empty?

      generated
    end

    if sap.nil?
      return render(json: {
        error: "Generated plan covered no controls, so nothing was saved. " \
               "If control_ids was supplied, check it matches the source's control " \
               "identifiers exactly — matching is case-insensitive but NOT " \
               "padding-insensitive, so \"ac-2\" does not match \"AC-02\"."
      }, status: :unprocessable_content)
    end

    audit_log("sap_document_generated", subject: sap, metadata: {
      name: sap.name, creation_method: "api",
      source_ssp_id: ssp&.id, source_profile_id: profile&.id,
      controls_count: sap.sap_controls.count
    })

    render json: { data: serialize_document(sap.reload, detailed: true) }, status: :created
  end

  # GET /api/v1/sap_documents/:id/export
  #
  # #1026 — the field-import endpoints below WRITE control fields, and until
  # this action existed nothing in the API read them back: `show` reports
  # `controls_count` and carries no `controls`. A caller could bulk-modify an
  # assessment plan's controls and had only the write's own `applied` count as
  # evidence, which is exactly the shape #994 was filed for.
  #
  # Same body as the SSP and SAR exports — `SapDocument#to_json_data` already
  # emitted `controls:` with each control's fields; only the route was missing.
  def export
    render json: JSON.parse(JsonExportService.export_sap(@document))
  end

  private

  def document_class = SapDocument
  def document_param_key = :sap_document
  def read_permission_key = "sap.read"
  def write_permission_key = "sap.write"

  # --- #844 generation helpers ---

  def generate_params
    @generate_params ||= permit_strictly(:sap_document,
      :name, :description, :authorization_boundary_id,
      :ssp_document_id, :profile_document_id,
      :assessment_type, :assessment_start, :assessment_end,
      control_ids: [], assessment_methods: {}
    )
  end

  def resolve_boundary
    id_or_slug = generate_params[:authorization_boundary_id].to_s
    return nil if id_or_slug.empty?

    if id_or_slug.match?(/\A\d+\z/)
      AuthorizationBoundary.find_by!(id: id_or_slug)
    else
      AuthorizationBoundary.find_by!(slug: id_or_slug)
    end
  end

  # Scoped to what the caller may actually read.
  #
  # An SSP carries the implementation narrative for every control, and the
  # generator copies that basis into the plan. Resolving an arbitrary
  # ssp_document_id would therefore let a caller pull another boundary's
  # control data out through a SAP they own — the same shape as #851, where a
  # permitted `*_id` had no boundary check. Admins are unscoped, as elsewhere.
  def resolve_ssp(boundary)
    id = generate_params[:ssp_document_id].presence
    return boundary&.ssp_document if id.nil?

    # #1025 — slug OR id. SSP documents are slug-addressed everywhere else, so
    # a caller who lists them and passes the slug back was told the document did
    # not exist. `find_by(id:)` against a slug matches nothing and raises
    # nothing: Postgres casts the string, finds no row, and the 404 blames the
    # document rather than the key.
    readable_ssps.find_by(slug: id) || readable_ssps.find_by(id: id) ||
      raise(ActiveRecord::RecordNotFound, "SSP document not found")
  end

  def readable_ssps
    return SspDocument.all if current_user.admin?

    SspDocument.where(authorization_boundary_id: current_user.authorization_boundaries.ids)
  end

  # Profiles carry no authorization_boundary — they are shared baselines, the
  # same class of artifact as a control catalog — so there is no per-boundary
  # scoping to apply here.
  def resolve_profile(boundary)
    id = generate_params[:profile_document_id].presence
    return boundary&.profile_document if id.nil?

    ProfileDocument.find(id)
  end

  def default_sap_name(boundary, ssp)
    subject = boundary&.name || ssp&.name || "Assessment Plan"
    "SAP — #{subject} — #{Date.current.iso8601}"
  end

  def document_params
    permit_strictly(:sap_document,
      :name, :description, :authorization_boundary_id,
      :ssp_document_id, :profile_document_id,
      :assessment_type, :assessment_start, :assessment_end,
      :sap_version, :lifecycle_status
    )
  end

  def serialize_document(doc, detailed: false)
    data = {
      id: doc.id,
      slug: doc.slug,
      uuid: doc.uuid,
      name: doc.name,
      status: doc.status,
      lifecycle_status: doc.lifecycle_status,
      authorization_boundary_id: doc.authorization_boundary_id,
      created_at: doc.created_at.iso8601,
      updated_at: doc.updated_at.iso8601
    }

    if detailed
      data[:description] = doc.description
      data[:assessment_type] = doc.assessment_type
      data[:assessment_start] = doc.assessment_start
      data[:assessment_end] = doc.assessment_end
      data[:sap_version] = doc.sap_version
      data[:controls_count] = doc.sap_controls.count
      data[:ssp_document_id] = doc.ssp_document_id
      data[:profile_document_id] = doc.profile_document_id
    end

    append_oscal_fields(data, doc, detailed: detailed)
  end
end
