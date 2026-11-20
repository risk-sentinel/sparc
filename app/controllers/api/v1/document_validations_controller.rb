# frozen_string_literal: true

# POST /api/v1/document_validations — check a document before sending it to,
# or after receiving it from, another system (#1354, #1384).
#
# Validates FedRAMP package JSON, OSCAL (JSON or XML), HDF and XCCDF against
# the schemas SPARC pins, and checks that every field those schemas require is
# filled in (DocumentValidationService). Nothing is stored: the response is
# the whole result.
#
# Payload: multipart/form-data with a `file` field, or the raw document as the
# request body. Optional parameters:
#   document_format  fedramp | oscal | hdf | xccdf (detected when omitted).
#                    Not `format`, which Rails keeps for the response format.
#   document_type    e.g. vulnerability-detail-report; for HDF, an hdf validate
#                    --type (results, amendments, system, ...)
#
# 200 with { valid: true|false, ... } whenever the document could be checked,
# valid or not; 422 only when it could not be checked at all (empty, not JSON
# or XML, an unknown format).
#
# NIST SP 800-53: IA-2 (Bearer token required), AC-3 (any authenticated
# caller; the endpoint reads and stores nothing of SPARC's), AU-12 (each check
# is audited by its result and the document's SHA-256, never its content),
# SI-10 (information input validation), CA-3 (information exchange).
class Api::V1::DocumentValidationsController < Api::V1::BaseController
  def create
    raw, filename = payload
    return render(json: { error: "No document supplied", note: "Send a multipart `file` field or the raw document as the request body" },
                  status: :unprocessable_content) if raw.blank?

    result = DocumentValidationService.call(raw, filename: filename,
                                                 format: params[:document_format].presence,
                                                 document_type: params[:document_type].presence)
    audit_log("document_validated", metadata: {
      format: result.format, document_type: result.document_type, valid: result.valid?,
      error_count: result.errors.size, sha256: Digest::SHA256.hexdigest(raw), filename: filename
    }.compact)
    render json: result.as_json
  rescue DocumentValidationService::Error, FedrampPackageSchemas::Error => e
    render json: { error: "The document could not be checked", details: e.message }, status: :unprocessable_content
  end

  private

  def payload
    if params[:file].respond_to?(:read)
      [ params[:file].read, params[:file].original_filename ]
    else
      [ request.raw_post.presence, nil ]
    end
  end
end
