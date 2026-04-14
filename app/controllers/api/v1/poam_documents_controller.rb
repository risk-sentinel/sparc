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
  private

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
