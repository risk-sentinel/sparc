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
# NIST 800-53 Controls:
#   AC-3 Access Enforcement (boundary-scoped RBAC)
#   AU-12 Audit Record Generation (all mutations logged)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
#
class Api::V1::SapDocumentsController < Api::V1::DocumentBaseController
  private

  def document_class = SapDocument
  def document_param_key = :sap_document
  def read_permission_key = "sap.read"
  def write_permission_key = "sap.write"

  def document_params
    params.require(:sap_document).permit(
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

    data
  end
end
