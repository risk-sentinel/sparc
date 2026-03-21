# REST API for System Security Plan (SSP) document management.
#
# All endpoints require Bearer token authentication.
# Non-admins see only SSP documents within their authorization boundaries.
#
# Standard CRUD:
#   GET    /api/v1/ssp_documents          — list (paginated, filterable)
#   GET    /api/v1/ssp_documents/:id      — show
#   POST   /api/v1/ssp_documents          — create
#   PUT    /api/v1/ssp_documents/:id      — update
#   DELETE /api/v1/ssp_documents/:id      — soft-delete
#
# Legacy actions (preserved, now with auth):
#   POST   /api/v1/ssp_documents/convert       — parse Excel to SSP
#   PUT    /api/v1/ssp_documents/:id/update_fields — bulk update control fields
#   GET    /api/v1/ssp_documents/:id/export    — export to JSON
#
# NIST 800-53 Controls:
#   IA-2 Identification and Authentication (Bearer token required)
#   AC-3 Access Enforcement (boundary-scoped RBAC)
#   AU-12 Audit Record Generation (all mutations logged)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
#
class Api::V1::SspDocumentsController < Api::V1::DocumentBaseController
  before_action :set_document, only: [ :show, :update, :destroy, :update_fields, :export ]
  before_action :authorize_document_read!, only: [ :show, :export ]
  before_action :authorize_document_write!, only: [ :create, :update, :destroy, :convert, :update_fields ]

  # POST /api/v1/ssp_documents/convert
  def convert
    uploaded_file = params[:excel_file]

    if uploaded_file.nil?
      render json: { error: "No file provided" }, status: :bad_request
      return
    end

    temp_file = Tempfile.new([ "ssp", File.extname(uploaded_file.original_filename) ])
    temp_file.binmode
    temp_file.write(uploaded_file.read)
    temp_file.rewind

    begin
      ssp_document = SspDocument.from_excel(temp_file.path, uploaded_file.original_filename)

      audit_log("ssp_document_imported", subject: ssp_document,
                metadata: { name: ssp_document.name, filename: uploaded_file.original_filename })

      render json: {
        success: true,
        message: "Conversion successful",
        data: ssp_document.to_json_data,
        document_id: ssp_document.id
      }
    rescue StandardError => e
      render json: { error: e.message }, status: :internal_server_error
    ensure
      temp_file.close
      temp_file.unlink
    end
  end

  # PUT /api/v1/ssp_documents/:id/update_fields
  def update_fields
    update_service = SspUpdateService.new(@document)

    begin
      update_service.bulk_update(params[:controls])

      audit_log("ssp_document_updated", subject: @document,
                metadata: { name: @document.name, controls_updated: params[:controls]&.keys&.length || 0 })

      render json: {
        success: true,
        message: "Controls updated successfully",
        data: @document.to_json_data
      }
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/ssp_documents/:id/export
  def export
    json_data = JsonExportService.export_ssp(@document)
    render json: JSON.parse(json_data)
  end

  private

  def document_class = SspDocument
  def document_param_key = :ssp_document
  def read_permission_key = "ssp.read"
  def write_permission_key = "ssp.write"

  def document_params
    params.require(:ssp_document).permit(
      :name, :description, :authorization_boundary_id, :profile_document_id,
      :system_status, :security_sensitivity_level, :ssp_version,
      :security_objective_confidentiality, :security_objective_integrity,
      :security_objective_availability, :lifecycle_status
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
      file_type: doc.file_type,
      creation_method: doc.creation_method,
      authorization_boundary_id: doc.authorization_boundary_id,
      created_at: doc.created_at.iso8601,
      updated_at: doc.updated_at.iso8601
    }

    if detailed
      data[:description] = doc.description
      data[:ssp_version] = doc.ssp_version
      data[:system_status] = doc.system_status
      data[:security_sensitivity_level] = doc.security_sensitivity_level
      data[:controls_count] = doc.ssp_controls.count
      data[:profile_document_id] = doc.profile_document_id
    end

    data
  end
end
