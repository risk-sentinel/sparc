# Shared OSCAL export validation endpoint for all document controllers.
#
# Including controllers must define these private methods:
#   oscal_export_document      — the ActiveRecord document instance
#   oscal_export_service(doc)  — the export service for the document type
#   oscal_document_type_label  — human-readable label (e.g., "SSP", "SAR")
#
# Provides:
#   validate_oscal_export (GET, JSON) — returns validation status for the
#     Stimulus-based export modal to decide whether to download directly
#     or prompt the user to confirm an unvalidated export.
module OscalExportable
  extend ActiveSupport::Concern

  # Shared across the including document controllers (resolved via ancestor
  # constant lookup) to avoid duplicating these literals per controller.
  JSON_CONTENT_TYPE = "application/json".freeze
  SCHEMA_VALIDATION_FAILED_FLASH =
    "OSCAL export failed schema validation. The export modal below has the specifics.".freeze

  # Public action — routable as GET validate_oscal_export
  def validate_oscal_export
    doc = oscal_export_document
    service = oscal_export_service(doc)
    result = service.validation_result

    render json: {
      valid: result.valid?,
      errors: result.valid? ? [] : result.errors.first(5),
      document_type: oscal_document_type_label
    }
  end
end
