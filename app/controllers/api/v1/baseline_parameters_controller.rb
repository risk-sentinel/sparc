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
  # #919 — found by spec/security/controller_authorization_coverage_spec.rb, NOT
  # by the original 16-controller survey, which looked only at the web surface.
  # `update` and `import_confirm` persist through BaselineParameterService with no
  # permission check, so any valid API token could rewrite a profile's baseline
  # parameters — the tailoring an ATO package rests on.
  #
  # profiles.write, unscoped, matching both the web and Api::V1 profile guards.
  before_action :authorize_profiles_write!, only: %i[update import_preview import_confirm]
  # #1008 — `profiles.write` answers "may this caller edit profiles", which is a
  # different question from "is this profile still editable". Only the first was
  # ever asked here, so a PUBLISHED baseline's parameters could be rewritten
  # through the API: 200, `parameters_updated: 1`, and the change persisted. The
  # Lifecycle concern has said "Published documents are read-only. Use the
  # duplication service to create an editable copy" since it was written;
  # nothing enforced it on this path.
  #
  # `import_preview` is a dry run and writes nothing, so it stays available on a
  # published profile — a reader may still ask what a file WOULD change.
  before_action :refuse_published_profile!, only: %i[update import_confirm]

  # GET /api/v1/profile_documents/:profile_document_id/parameters
  def show
    service = BaselineParameterService.new(@profile)
    schema = service.extract_schema(family: params[:family])

    render json: { data: schema }
  end

  # PUT /api/v1/profile_documents/:profile_document_id/parameters
  #
  # #994 — the payload is parsed and REFUSED before the service sees it. This
  # endpoint used to answer 200 with `parameters_updated: 0` for bodies it had
  # never understood, because `params.permit` discards an unrecognised shape
  # silently and the resulting empty arrays are indistinguishable from a caller
  # who asked for nothing. See BaselineParameterPayload for the full account.
  def update
    payload = BaselineParameterPayload.parse(params)
    unless payload.valid?
      return render json: {
        error:    "The request body could not be parsed as a baseline parameter update. Nothing was changed.",
        details:  payload.errors,
        expected: BaselineParameterPayload::EXPECTED
      }, status: :unprocessable_entity
    end

    service = BaselineParameterService.new(@profile)
    result = service.update_parameters(payload.to_h)

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

  # #1008 — a published profile is what other documents are derived from and
  # attested against. Editing one after publication moves the basis of every
  # SSP built on it, so it is refused with a reason naming the way forward
  # rather than a bare 403.
  def refuse_published_profile!
    return unless @profile.published_lifecycle?

    render json: {
      error: "This profile is published and cannot be edited. Duplicate it to create an editable draft.",
      details: [ "lifecycle_status is \"published\"" ]
    }, status: :unprocessable_entity
  end

  # #574 — accept either numeric id or slug; same rationale as the
  # ksi_validations and #566 fixes.
  def authorize_profiles_write!
    return if current_user&.admin?
    return if current_user&.has_permission?("profiles.write")

    render json: { error: "Forbidden" }, status: :forbidden
  end

  def set_profile
    id_or_slug = params[:profile_document_id].to_s
    @profile = if id_or_slug.match?(/\A\d+\z/)
      ProfileDocument.find_by!(id: id_or_slug)
    else
      ProfileDocument.find_by!(slug: id_or_slug)
    end
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
