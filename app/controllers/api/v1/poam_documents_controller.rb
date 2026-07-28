# REST API for Plan of Action and Milestones (POA&M) document management.
#
# All endpoints require Bearer token authentication.
# Non-admins see only POA&M documents within their authorization boundaries.
#
# Standard CRUD:
#   GET    /api/v1/poam_documents          — list (paginated, filterable)
#   GET    /api/v1/poam_documents/:id      — show
#   POST   /api/v1/poam_documents          — create
#   PUT    /api/v1/poam_documents/:id      — update
#   DELETE /api/v1/poam_documents/:id      — soft-delete
#
# NIST 800-53 Controls:
#   AC-3 Access Enforcement (boundary-scoped RBAC)
#   AU-12 Audit Record Generation (all mutations logged)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
#
class Api::V1::PoamDocumentsController < Api::V1::DocumentBaseController
  before_action :authorize_document_write!, only: [ :create, :update, :destroy, :generate ]

  # POST /api/v1/poam_documents/generate
  #
  # #843 — build a POA&M from a SAR's open risks. Until now POA&M was the only
  # document in the authorization chain with no generator at all: it could
  # enter SPARC only by importing externally-authored OSCAL or by
  # hand-assembling the item/risk/finding/observation graph record by record.
  # That broke "run the whole lifecycle in one tool" at the last mile — and the
  # POA&M is the artifact customers touch monthly, not once at authorization.
  #
  # Responds 201 even when some source risks could not be converted. That is
  # not a partial failure to paper over: the POA&M genuinely was created, and
  # the risks that were left out are listed in `skipped` with a reason each, so
  # the caller can act on them. Returning an error would discard a valid POA&M
  # over source data the assessor still has to fix.
  def generate
    boundary = resolve_boundary
    sar = resolve_sar(boundary)

    result = PoamGeneratorService.new(
      name: generate_params[:name].presence || default_poam_name(boundary, sar),
      description: generate_params[:description],
      sar_document: sar,
      authorization_boundary: boundary
    ).generate

    audit_log("poam_document_generated", subject: result.poam_document, metadata: {
      name: result.poam_document.name, creation_method: "api",
      source_sar_id: sar&.id, items: result.created_items, skipped: result.skipped_count
    })

    render json: {
      data: serialize_document(result.poam_document, detailed: true),
      meta: {
        items_created: result.created_items,
        risks_created: result.created_risks,
        findings_created: result.created_findings,
        complete: result.complete?
      },
      skipped: result.skipped
    }, status: :created
  end

  private

  def generate_params
    @generate_params ||= params.require(:poam_document).permit(
      :name, :description, :authorization_boundary_id, :sar_document_id
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

  # Scoped to what the caller may read. A SAR carries the assessment's findings
  # and this copies them into a POA&M the caller owns, so resolving an
  # arbitrary sar_document_id would expose another boundary's assessment
  # results — the same shape as #851.
  def resolve_sar(boundary)
    id = generate_params[:sar_document_id].presence
    return boundary&.sar_document if id.nil?

    readable_sars.find_by(id: id) || raise(ActiveRecord::RecordNotFound, "SAR document not found")
  end

  def readable_sars
    return SarDocument.all if current_user.admin?

    SarDocument.where(authorization_boundary_id: current_user.authorization_boundaries.ids)
  end

  def default_poam_name(boundary, sar)
    "POA&M — #{boundary&.name || sar&.name || 'Boundary'} — #{Date.current.iso8601}"
  end

  def document_class = PoamDocument
  def document_param_key = :poam_document
  def read_permission_key = "poam.read"
  def write_permission_key = "poam.write"

  def document_params
    params.require(:poam_document).permit(
      :name, :description, :authorization_boundary_id,
      :poam_version, :system_id, :lifecycle_status
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
      data[:poam_version] = doc.poam_version
      data[:system_id] = doc.system_id
      data[:items_count] = doc.poam_items.count
      data[:risks_count] = doc.poam_risks.count
      data[:findings_count] = doc.poam_findings.count
      data[:observations_count] = doc.poam_observations.count
    end

    append_oscal_fields(data, doc, detailed: detailed)
  end
end
