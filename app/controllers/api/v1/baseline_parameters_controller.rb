# REST API for baseline parameter and enumeration management.
#
# Provides read, update, and export of OSCAL parameters and
# enumeration selections for a profile document (baseline).
#
# All endpoints require Bearer token authentication.
# Nested under /api/v1/profile_documents/:profile_document_id/parameters
#
# GET    .../parameters          — parameter schema for the baseline
# PUT    .../parameters          — update parameter values
# GET    .../parameters/export   — export as JSON, YAML, or XML
#
# NIST 800-53 Controls:
#   AC-3 Access Enforcement (Bearer token auth on all endpoints)
#   AU-12 Audit Record Generation (parameter updates logged)
#   CM-6 Configuration Settings (baseline parameter customization)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
#
class Api::V1::BaselineParametersController < Api::V1::BaseController
  before_action :set_profile

  # GET /api/v1/profile_documents/:profile_document_id/parameters
  def show
    service = BaselineParameterService.new(@profile)
    schema = service.extract_schema(family: params[:family])

    render json: { data: schema }
  end

  # PUT /api/v1/profile_documents/:profile_document_id/parameters
  def update
    service = BaselineParameterService.new(@profile)
    result = service.update_parameters(parameter_payload)

    audit_log("profile_document_updated",
      subject: @profile,
      metadata: {
        name: @profile.name,
        action: "parameter_update",
        parameters_updated: result[:parameters_updated],
        selections_updated: result[:selections_updated]
      }
    )

    status = result[:validation_errors].any? ? :unprocessable_entity : :ok
    render json: { data: result }, status: status
  end

  # POST /api/v1/profile_documents/:profile_document_id/parameters/import/preview
  # #697 (P0) — non-destructive dry-run of an uploaded ODP file (JSON/YAML/XML).
  # Returns the classified diff (change / unchanged / unknown / invalid) with no
  # writes. Multipart `:file`; `format` inferred from the filename unless given.
  #
  # NIST 800-53: SI-10 (input validation), CM-3 (change preview).
  def import_preview
    payload = parse_import_file
    result = OdpImportService.new(@profile).preview(payload)
    render json: {
      data: {
        profile_id:   @profile.id,
        profile_slug: @profile.slug,
        stats:        result[:stats],
        rows:         result[:rows].map(&:to_h)
      }
    }
  rescue OdpImportService::ImportError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST /api/v1/profile_documents/:profile_document_id/parameters/import/confirm
  # #697 (P0) — apply an uploaded ODP file atomically via the existing baseline
  # update path, with partial-success reporting (unknown ids skipped, invalid
  # selection choices dropped). Audited (AU-12). Returns 422 only when nothing
  # could be applied.
  def import_confirm
    payload = parse_import_file
    result  = OdpImportService.new(@profile).apply(payload)

    audit_log("profile_document_updated",
      subject: @profile,
      metadata: {
        name: @profile.name,
        action: "odp_file_import",
        parameters_updated: result[:parameters_updated],
        selections_updated: result[:selections_updated],
        validation_errors: result[:validation_errors].size
      }
    )

    applied = result[:parameters_updated] + result[:selections_updated]
    status = (applied.zero? && result[:validation_errors].any?) ? :unprocessable_entity : :ok
    render json: { data: result }, status: status
  rescue OdpImportService::ImportError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # GET /api/v1/profile_documents/:profile_document_id/parameters/export
  def export
    format = (params[:format].presence || "json").to_sym
    unless %i[json yaml xml].include?(format)
      return render json: { error: "Unsupported format. Use json, yaml, or xml" }, status: :bad_request
    end

    service = BaselineParameterService.new(@profile)
    content = service.export(format: format)

    content_types = { json: "application/json", yaml: "text/yaml", xml: "application/xml" }
    filename = "#{@profile.slug}-parameters.#{format}"

    send_data content,
      filename: filename,
      type: content_types[format],
      disposition: "attachment"
  end

  private

  # #574 — accept either numeric id or slug; same rationale as the
  # ksi_validations and #566 fixes.
  def set_profile
    id_or_slug = params[:profile_document_id].to_s
    @profile = if id_or_slug.match?(/\A\d+\z/)
      ProfileDocument.find_by!(id: id_or_slug)
    else
      ProfileDocument.find_by!(slug: id_or_slug)
    end
  end

  def parameter_payload
    params.permit(
      parameters: [ :param_id, :value ],
      selections: [ :select_id, selected: [] ]
    ).to_h.deep_symbolize_keys
  end

  # #697 — SI-10 upload guard: cap the ODP import file size (consistent with the
  # existing multipart hardening) and normalize it to the canonical payload.
  MAX_IMPORT_BYTES = 5.megabytes

  def parse_import_file
    upload = params[:file]
    unless upload.respond_to?(:read)
      raise OdpImportService::ImportError, "Provide a multipart :file upload (JSON, YAML, or XML)"
    end
    if upload.respond_to?(:size) && upload.size > MAX_IMPORT_BYTES
      raise OdpImportService::ImportError, "File exceeds the #{MAX_IMPORT_BYTES / 1.megabyte}MB import limit"
    end

    content = upload.read.to_s
    if content.bytesize > MAX_IMPORT_BYTES
      raise OdpImportService::ImportError, "File exceeds the #{MAX_IMPORT_BYTES / 1.megabyte}MB import limit"
    end

    format = params[:format].presence ||
             File.extname(upload.try(:original_filename).to_s).delete_prefix(".").presence ||
             "json"
    OdpImportService.parse(content: content, format: format)
  end
end
