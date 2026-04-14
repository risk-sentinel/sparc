# REST API for Security Assessment Results (SAR) document management.
#
# All endpoints require Bearer token authentication.
# Non-admins see only SAR documents within their authorization boundaries.
#
# Standard CRUD:
#   GET    /api/v1/sar_documents          — list (paginated, filterable)
#   GET    /api/v1/sar_documents/:id      — show
#   POST   /api/v1/sar_documents          — create
#   PUT    /api/v1/sar_documents/:id      — update
#   DELETE /api/v1/sar_documents/:id      — soft-delete
#
# Legacy actions:
#   POST   /api/v1/sar_documents/convert       — parse Excel to SAR
#   PUT    /api/v1/sar_documents/:id/update_fields — bulk update control fields
#   GET    /api/v1/sar_documents/:id/export    — export to JSON
#
# NIST 800-53 Controls:
#   AC-3 Access Enforcement (boundary-scoped RBAC)
#   AU-12 Audit Record Generation (all mutations logged)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
#
class Api::V1::SarDocumentsController < Api::V1::DocumentBaseController
  before_action :set_document, only: [ :show, :update, :destroy, :update_fields, :export ]
  before_action :authorize_document_read!, only: [ :show, :export ]
  before_action :authorize_document_write!, only: [ :create, :update, :destroy, :convert, :update_fields ]

  # POST /api/v1/sar_documents/convert
  def convert
    uploaded_file = params[:excel_file]

    if uploaded_file.nil?
      render json: { error: "No file provided" }, status: :bad_request
      return
    end

    temp_file = Tempfile.new([ "sar", File.extname(uploaded_file.original_filename) ])
    temp_file.binmode
    temp_file.write(uploaded_file.read)
    temp_file.rewind

    begin
      sar_document = SarDocument.create!(
        name: File.basename(uploaded_file.original_filename, ".*"),
        file_type: "excel",
        original_filename: uploaded_file.original_filename,
        status: "processing"
      )

      SarExcelParserService.new(sar_document, temp_file.path).parse
      sar_document.update!(status: "completed")

      audit_log("sar_document_imported", subject: sar_document,
                metadata: { name: sar_document.name, filename: uploaded_file.original_filename })

      render json: {
        success: true,
        message: "Conversion successful",
        data: sar_document.to_json_data,
        document_id: sar_document.id
      }
    rescue StandardError => e
      sar_document&.update!(status: "failed")
      render json: { error: e.message }, status: :internal_server_error
    ensure
      temp_file.close
      temp_file.unlink
    end
  end

  # PUT /api/v1/sar_documents/:id/update_fields
  def update_fields
    begin
      controls = params[:controls] || {}
      controls.each do |control_id, field_updates|
        control = @document.sar_controls.find_by!(control_id: control_id)
        field_updates.each do |field_name, field_value|
          field = control.sar_control_fields.find_by!(field_name: field_name)
          field.update!(field_value: field_value) if field.editable?
        end
      end

      audit_log("sar_document_updated", subject: @document,
                metadata: { name: @document.name, controls_updated: controls.keys.length })

      render json: {
        success: true,
        message: "Controls updated successfully",
        data: @document.to_json_data
      }
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/sar_documents/:id/export
  def export
    json_data = JsonExportService.export_sar(@document)
    render json: JSON.parse(json_data)
  end

  private

  def document_class = SarDocument
  def document_param_key = :sar_document
  def read_permission_key = "sar.read"
  def write_permission_key = "sar.write"

  def document_params
    params.require(:sar_document).permit(
      :name, :description, :authorization_boundary_id,
      :sap_document_id, :profile_document_id, :ssp_document_id,
      :lifecycle_status
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
      data[:controls_count] = doc.sar_controls.count
      data[:sap_document_id] = doc.sap_document_id
      data[:profile_document_id] = doc.profile_document_id
      data[:ssp_document_id] = doc.ssp_document_id
    end

    append_oscal_fields(data, doc, detailed: detailed)
  end
end
