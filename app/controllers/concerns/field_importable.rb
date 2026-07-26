# frozen_string_literal: true

# #716 — shared preview/confirm actions for bulk control-field file import,
# included by the SSP / SAR / SAP / CDEF API controllers. The heavy lifting is
# in FieldImportService; this concern handles the multipart upload, size guard
# (SI-10), and the JSON envelope + audit. Each including controller must:
#   - run its own set_document + write-authorization before_actions for
#     :import_fields_preview / :import_fields_confirm, and
#   - define `field_import_document` returning the loaded, authorized document.
module FieldImportable
  extend ActiveSupport::Concern

  # POST .../fields/import/preview — non-destructive diff.
  def import_fields_preview
    result = FieldImportService.new(field_import_document).preview(field_import_payload)
    render json: { data: { rows: result[:rows].map(&:to_h), stats: result[:stats] } }
  rescue FieldImportService::ImportError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # POST .../fields/import/confirm — atomic apply with partial-success + audit.
  def import_fields_confirm
    doc = field_import_document
    result = FieldImportService.new(doc).apply(field_import_payload)
    audit_log("#{doc.class.name.underscore}_fields_imported", subject: doc,
              metadata: { applied: result[:applied], stats: result[:stats] })
    render json: { data: result }
  rescue FieldImportService::ImportError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  # Read + guard the uploaded file, then parse to the canonical payload.
  def field_import_payload
    upload = params[:file]
    unless upload.respond_to?(:read)
      raise FieldImportService::ImportError, "No file provided (multipart field :file)"
    end

    content = upload.read
    max = SparcConfig.max_upload_bytes
    if content.to_s.bytesize > max
      raise FieldImportService::ImportError, "File exceeds the #{max}-byte upload limit"
    end

    fmt = params[:format].presence || File.extname(upload.original_filename.to_s).delete_prefix(".")
    FieldImportService.parse(content: content, format: fmt)
  end
end
