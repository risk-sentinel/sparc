# Generates a ZIP containing the OSCAL exports for every document linked to an
# Authorization Boundary, plus a manifest describing exactly what is inside.
#
# Usage:
#   service  = AtoPackageExportService.new(authorization_boundary)
#   zip_data = service.generate_zip                      # JSON, YAML and XML
#   zip_data = service.generate_zip(formats: [ :json ])  # one serialization
#   summary  = service.validation_summary
#
# #829 — the package used to be JSON-only. Every other OSCAL export in SPARC is
# available in JSON, YAML and XML, and `download_xml` is a user-facing route on
# seven document types; the ATO package — the artifact an assessor or AO
# actually receives — was the one place offering a single serialization, so
# consumers standardised on OSCAL XML could not use it at all.
#
# #828 — the manifest used to be built from the boundary's ASSOCIATIONS while
# the archive was built from exports that could fail. When one did, the entry
# was silently skipped and the manifest went on listing a file that was not in
# the archive; the only trace was a server-side log line. A package that claims
# to contain an SSP and does not is worse than an export that fails outright,
# because nothing signals the loss.
#
# The fix is structural rather than a matching pair of edits: exports are run
# FIRST, and both the archive and the manifest are derived from the SAME
# results. The two cannot disagree, because there is only one source.
require "zip"

class AtoPackageExportService
  EXPORT_SERVICES = {
    ssp:  OscalSspExportService,
    sap:  OscalAssessmentPlanExportService,
    sar:  OscalSarExportService,
    poam: OscalPoamExportService,
    cdef: OscalComponentDefinitionExportService
  }.freeze

  # The OSCAL model each document type validates against. Needed because the
  # schema key is not always the document key (`cdef` is `component_definition`).
  MODEL_TYPES = {
    ssp:  :ssp,
    sap:  :assessment_plan,
    sar:  :assessment_results,
    poam: :poam,
    cdef: :component_definition
  }.freeze

  FORMATS = %i[json yaml xml].freeze

  # The archive ships UNVALIDATED exports deliberately: a partial package is
  # still recoverable, and an AO chasing a problem needs to see the document
  # that has it. What #828 required is that this is stated unambiguously per
  # document rather than left implicit — so every file records `schema_valid`,
  # and the manifest says outright what these bytes are.
  CONTENTS_NOTE = "Documents are exported WITHOUT gating on schema validation, so a " \
                  "package remains recoverable when a document does not yet conform. " \
                  "`schema_valid` on each file states whether that serialization " \
                  "passes its OSCAL schema. Do not treat presence in this archive as " \
                  "evidence of conformance.".freeze

  def initialize(authorization_boundary)
    @ab = authorization_boundary
  end

  def generate_zip(formats: FORMATS)
    formats = Array(formats).map(&:to_sym) & FORMATS
    formats = FORMATS if formats.empty?
    results = export_results(formats)

    buffer = Zip::OutputStream.write_buffer do |zip|
      results.each do |result|
        result[:files].each do |file|
          zip.put_next_entry(file[:file])
          zip.write(file[:body])
        end
      end

      zip.put_next_entry("manifest.json")
      zip.write(JSON.pretty_generate(manifest(results, formats)))
    end
    buffer.string
  end

  def validation_summary
    summary = {}

    { ssp: @ab.ssp_document, sap: @ab.sap_document, sar: @ab.sar_document }.each do |key, doc|
      summary[key] = validate_document(key, doc)
    end

    @ab.poam_documents.each_with_index do |poam, i|
      summary[:"poam_#{i + 1}"] = validate_document(:poam, poam)
    end

    @ab.cdef_documents.distinct.each do |cdef|
      summary[:"cdef_#{cdef.slug}"] = validate_document(:cdef, cdef)
    end

    summary
  end

  private

  # Every document the boundary carries, as [type, basename, document].
  def planned_documents
    planned = []
    planned << [ :ssp, "ssp", @ab.ssp_document ] if @ab.ssp_document
    planned << [ :sap, "sap", @ab.sap_document ] if @ab.sap_document
    planned << [ :sar, "sar", @ab.sar_document ] if @ab.sar_document

    @ab.poam_documents.each_with_index { |poam, i| planned << [ :poam, "poam-#{i + 1}", poam ] }
    @ab.cdef_documents.distinct.each { |cdef| planned << [ :cdef, "cdef-#{cdef.slug}", cdef ] }

    planned
  end

  # Run every export up front. A document that fails is recorded as OMITTED with
  # its error rather than silently dropped, and the manifest is built from this
  # same list — so it can only ever describe what the archive really contains.
  def export_results(formats)
    planned_documents.map do |type, basename, document|
      begin
        json = EXPORT_SERVICES[type].new(document).export_unvalidated
        { type: type, name: document.name, files: serialize(json, type, basename, formats) }
      rescue StandardError => e
        Rails.logger.warn("ATO export: failed to export #{type} #{document.id}: #{e.message}")
        { type: type, name: document.name, files: [], error: e.message }
      end
    end
  end

  # Convert one exported document into each requested serialization, recording
  # whether that serialization passes its OSCAL schema.
  #
  # A format that cannot be rendered at all is dropped from THIS document
  # rather than failing the whole package — the other serializations are still
  # usable. That is not a silent loss: the manifest's `files` list is built from
  # what was actually produced, so a missing format is visible there by absence
  # rather than being listed and then not written (the #828 failure mode).
  def serialize(json, type, basename, formats)
    model = MODEL_TYPES.fetch(type)

    formats.filter_map do |format|
      begin
        body = case format
        when :json then json
        when :yaml then OscalExportFormatService.to_yaml(json)
        when :xml  then OscalExportFormatService.to_xml(json, model)
        end

        { file: "#{basename}.#{format}", format: format.to_s, body: body,
          schema_valid: schema_valid?(model, format, body) }
      rescue StandardError => e
        Rails.logger.warn("ATO export: #{basename} could not be rendered as #{format}: #{e.message}")
        nil
      end
    end
  end

  # JSON and YAML share the JSON Schema; XML is checked against the NIST XSD,
  # which is a genuinely different model with its own element-ordering rules.
  def schema_valid?(model, format, body)
    result = case format
    when :json then OscalSchemaValidationService.validate_json(model, body)
    when :yaml then OscalSchemaValidationService.validate(
               model, YAML.safe_load(body, permitted_classes: [ Date, Time, DateTime ], aliases: true)
             )
    when :xml then OscalSchemaValidationService.validate_xml(model, body)
    end
    result.valid?
  rescue StandardError
    false
  end

  def manifest(results, formats)
    written = results.reject { |r| r[:files].empty? }
    omitted = results.select { |r| r[:files].empty? }

    {
      "authorization_boundary" => {
        "name" => @ab.name,
        "status" => @ab.status,
        "generated_at" => Time.current.iso8601
      },
      "export" => {
        "serializations" => formats.map(&:to_s),
        "contents" => "unvalidated",
        "note" => CONTENTS_NOTE
      },
      "documents" => written.map { |r| manifest_entry(r) },
      # #828 — a failed export is stated in the artifact the customer receives,
      # not only in a server log they cannot see.
      "omitted" => omitted.map do |r|
        { "type" => r[:type].to_s, "name" => r[:name], "error" => r[:error] }
      end,
      "validation" => validation_summary.transform_values { |v| v[:valid] }
    }
  end

  def manifest_entry(result)
    {
      "type" => result[:type].to_s,
      "name" => result[:name],
      # Retained so consumers written against the old single-file manifest keep
      # working; `files` is the complete picture.
      "file" => result[:files].first[:file],
      "files" => result[:files].map do |f|
        { "file" => f[:file], "format" => f[:format], "schema_valid" => f[:schema_valid] }
      end
    }
  end

  def validate_document(type, document)
    return { name: nil, valid: nil, errors: [ "Not linked" ] } unless document

    service = EXPORT_SERVICES[type].new(document)
    result = service.validation_result
    {
      name: document.name,
      valid: result.valid?,
      errors: result.valid? ? [] : result.errors.first(3)
    }
  rescue StandardError => e
    { name: document&.name, valid: false, errors: [ e.message ] }
  end
end
