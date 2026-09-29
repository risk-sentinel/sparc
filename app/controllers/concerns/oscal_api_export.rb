# Shared `GET /api/v1/<documents>/:id/export` behaviour for every document an
# API caller can export as OSCAL (#1029 CDEF, #1181 SSP/SAP/SAR/POA&M, #1154
# mapping collections).
#
# #1029 proved the shape on cdef_documents; #1181 found the other document
# types had working OSCAL exporters that only the browser could reach, because
# the web routes sit behind session authentication a service account cannot
# hold. One implementation, so the five surfaces cannot drift apart:
#
#   format=fields (default) SPARC's own control-field JSON (JsonExportService)
#                           — unchanged, so existing callers are unaffected.
#                           Not offered where no such export exists (mappings).
#   format=oscal            the OSCAL document, JSON
#   format=oscal-yaml       the same document as YAML
#   format=oscal-xml        the same document as XML (only where SPARC carries
#                           the model's XSD and element order)
#
#   validate=true (default) validates the OSCAL JSON against the NIST schema and
#   REFUSES a document that does not conform — a 422 naming the errors, not a
#   file the caller discovers is unusable later. `validate=false` is the
#   deliberate escape hatch (`export_unvalidated`). YAML and XML are serialised
#   from that same (validated) JSON, exactly as the web downloads are.
#
# Conditional GET (#1154 part 3 — Horizon pulls with ETag caching). The strong
# ETag digests the document id, its updated_at, the format, the validate flag,
# OscalSchema::DEFAULT_VERSION AND the exported bytes. The bytes are in the key
# because updated_at alone is NOT a change signal for these documents: a
# control field, a POA&M item, a component or a back-matter resource changes
# without touching its parent document (only mapping entries `touch:` their
# parent), so an updated_at-only ETag would answer 304 over content that had
# changed — a stale document served as current. The cost of correctness is that
# a 304 still builds (and validates) the export; what it saves is the transfer.
#
# Including controllers call `render_oscal_api_export` from their `export`
# action, AFTER their own before_actions have loaded and authorized the record
# — this concern does no authorization of its own.
#
# NIST 800-53 Controls:
#   AC-3 Access Enforcement (authorization stays with the including controller)
#   AU-12 Audit Record Generation (every delivered OSCAL export is logged)
#   SI-10 Information Input Validation (format / validate are closed sets)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
module OscalApiExport
  extend ActiveSupport::Concern

  OSCAL_EXPORT_FORMATS = %w[oscal oscal-yaml oscal-xml].freeze
  FIELDS_FORMAT = "fields".freeze
  UNVALIDATED_HINT = "Re-request with validate=false to export it anyway".freeze

  private

  # document:      the loaded, already-authorized record
  # service:       an OSCAL export service instance (`export`, `export_unvalidated`)
  # xml_model:     OscalJsonToXmlConverter model type, or nil when XML is not offered
  # label:         noun phrase for the refusal ("component definition")
  # audit_action:  AuditEvent action logged on a delivered OSCAL export
  # fields:        callable returning SPARC's field JSON string, or nil when the
  #                type has none (then `oscal` is the default format)
  # xml_refusal:   why XML is not offered, when xml_model is nil
  def render_oscal_api_export(document:, service:, xml_model:, label:, audit_action:,
                              fields: nil, xml_refusal: nil)
    formats = offered_oscal_formats(fields: fields, xml_model: xml_model)
    format  = params[:format].presence&.to_s || formats.first

    unless formats.include?(format)
      body = { error: "Unknown export format #{format.inspect}", expected: formats }
      body[:reason] = xml_refusal if format == "oscal-xml" && xml_refusal
      return render json: body, status: :unprocessable_content
    end

    if format == FIELDS_FORMAT
      json_string = fields.call
      return unless oscal_export_stale?(document, format, nil, json_string)

      return render json: JSON.parse(json_string)
    end

    validate    = params[:validate].to_s != "false"
    json_string = validate ? service.export : service.export_unvalidated
    return unless oscal_export_stale?(document, format, validate, json_string)

    audit_log(audit_action, subject: document,
              metadata: { name: document.name, format: format, validated: validate })

    case format
    when "oscal"      then render json: JSON.parse(json_string)
    when "oscal-yaml" then render plain: OscalExportFormatService.to_yaml(json_string),
                                   content_type: "application/x-yaml"
    when "oscal-xml"  then render xml: OscalExportFormatService.to_xml(json_string, xml_model)
    else
      # Unreachable: the guard above admits only offered formats. Present so
      # that ADDING a format and forgetting to handle it here is a named error
      # in the log rather than a silent empty 204 — a `case` with no else
      # returns nil, and Rails answers a nil render with no content.
      raise ArgumentError, "Unhandled export format #{format.inspect}"
    end
  rescue OscalValidationError => e
    # Named, and pointing at the way out. A caller who wants the document
    # anyway can ask for it; what they must not get is a silent 500 or a file
    # that claims to be OSCAL and is not.
    render json: {
      error: "The #{label} does not conform to the OSCAL schema",
      details: Array(e.message.to_s.split("\n")).first(10),
      hint: UNVALIDATED_HINT
    }, status: :unprocessable_content
  end

  def offered_oscal_formats(fields:, xml_model:)
    offered = []
    offered << FIELDS_FORMAT if fields
    offered.concat(OSCAL_EXPORT_FORMATS)
    offered.delete("oscal-xml") unless xml_model
    offered
  end

  # Sets the strong ETag and answers 304 when the caller already holds this
  # exact export. Returns true when the body must still be rendered.
  def oscal_export_stale?(document, format, validate, body)
    stale?(strong_etag: [
      document.class.name, document.id, document.updated_at&.utc&.iso8601(6),
      format, validate, OscalSchema::DEFAULT_VERSION,
      Digest::SHA256.hexdigest(body.to_s)
    ], template: false)
  end
end
