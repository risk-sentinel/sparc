# frozen_string_literal: true

require "json"
require "stringio"

# One validator for every document format SPARC exchanges with other systems:
# FedRAMP package JSON, OSCAL (JSON or XML), HDF and XCCDF (#1354, #1384).
#
# Two checks, both against the schema SPARC pins for the format:
#   1. schema       — is the document well formed by its schema?
#   2. completeness — is every field the schema requires filled in, not just
#                     present (SchemaCompleteness)? FedRAMP packages also get
#                     a warning for each optional field left empty.
#
# Errors make a document invalid. Warnings are reported, never blocking.
# The service persists nothing: uploads, pulls and the
# POST /api/v1/document_validations endpoint all call it.
#
#   result = DocumentValidationService.call(raw_bytes, filename: "sdr.json")
#   result.valid?          # => false
#   result.format          # => "fedramp"
#   result.document_type   # => "security-decision-record"
#   result.errors          # => [{ check: "completeness", pointer: "/...", message: "required field is blank" }]
#
# NIST SP 800-53: SI-10 (information input validation), SI-7 (the schemas are
# the pinned, vendored copies), CA-3 / SA-9 (documents exchanged with external
# systems are checked before SPARC accepts them).
class DocumentValidationService
  class Error < StandardError; end

  FORMATS = %w[fedramp oscal hdf xccdf].freeze
  OSCAL_XML_NAMESPACE = "http://csrc.nist.gov/ns/oscal/1.0"
  MAX_ERRORS = 200

  Result = Struct.new(:format, :document_type, :schema, :errors, :warnings, :warnings_total, keyword_init: true) do
    def valid? = errors.empty?

    def as_json(*)
      { valid: valid?, format: format, document_type: document_type, schema: schema,
        errors: errors, warnings: warnings, warnings_total: warnings_total }
    end
  end

  def self.call(content, filename: nil, format: nil, document_type: nil)
    new(content, filename: filename, format: format, document_type: document_type).call
  end

  def initialize(content, filename: nil, format: nil, document_type: nil)
    @raw = content.to_s
    @filename = filename
    @format = format.presence&.to_s
    @document_type = document_type.presence&.to_s
  end

  def call
    raise Error, "Empty document" if @raw.strip.empty?

    max = SparcConfig.max_upload_bytes
    raise Error, "Document exceeds the #{max}-byte upload limit" if @raw.bytesize > max
    raise Error, "Unknown format '#{@format}'. Known: #{FORMATS.join(', ')}" if @format && !FORMATS.include?(@format)

    xml? ? validate_xml : validate_json
  end

  private

  def xml? = @raw.lstrip.start_with?("<")

  # ── JSON: FedRAMP, OSCAL, HDF ──────────────────────────────────────

  def validate_json
    data = JSON.parse(@raw)
    format = @format || detect_json_format(data)
    case format
    when "fedramp" then validate_fedramp(data)
    when "oscal" then validate_oscal_json(data)
    when "hdf" then validate_hdf(data)
    when "xccdf" then raise Error, "XCCDF is XML; this document is JSON"
    else
      raise Error, "Could not tell which format this document is. Name it with format (#{FORMATS.join(', ')})"
    end
  rescue JSON::ParserError => e
    raise Error, "Not valid JSON: #{e.message.lines.first.to_s.strip}"
  end

  def detect_json_format(data)
    if data.is_a?(Hash)
      return "fedramp" if data["$schema"].to_s.match?(%r{\Ahttps?://(www\.)?fedramp\.gov/schemas/})
      return "oscal" if (data.keys & oscal_root_keys).any?
      return "hdf" if data.key?("profiles") || data.key?("baselines")
      return "fedramp" if fedramp_type_from_shape(data)
    elsif data.is_a?(Array) && data.first.is_a?(Hash) && (data.first.key?("profiles") || data.first.key?("baselines"))
      return "hdf" # a `saf convert` bundle
    end
    nil
  end

  def validate_fedramp(data)
    raise Error, "A FedRAMP package document is a JSON object" unless data.is_a?(Hash)

    schema = fedramp_schema_for(data)
    schemer = FedrampPackageSchemas.schemer(schema.document_type)
    errors = schemer.validate(data).first(MAX_ERRORS).map { |e| finding("schema", e["data_pointer"], e["error"]) }
    completeness = SchemaCompleteness.new(schema.document, resolver: FedrampPackageSchemas.ref_resolver,
                                                           warn_optional: true).check(data)

    result(format: "fedramp", document_type: schema.document_type,
           schema: { name: schema.file, id: schema.id, version: schema.version, sha256: schema.sha256 },
           errors: errors + completeness.errors.map { |f| finding("completeness", f.pointer, f.message) },
           completeness: completeness)
  end

  # The document's own `$schema`, then the caller's document_type, then the
  # schema whose required top-level fields the document has.
  def fedramp_schema_for(data)
    if data["$schema"].present?
      named = FedrampPackageSchemas.for_schema_uri(data["$schema"])
      raise Error, "$schema #{data['$schema']} is not a FedRAMP schema SPARC carries" unless named
      if @document_type && @document_type != named.document_type
        raise Error, "document_type #{@document_type} does not match the document's $schema (#{named.document_type})"
      end

      return named
    end
    return FedrampPackageSchemas.fetch(@document_type) if @document_type

    type = fedramp_type_from_shape(data)
    raise Error, "Could not tell which FedRAMP document this is. Set $schema in the document, or name its document_type" unless type

    FedrampPackageSchemas.fetch(type)
  end

  # The one schema whose required top-level fields are all present, preferring
  # the schema that requires the most of them. A tie is not a guess.
  def fedramp_type_from_shape(data)
    candidates = FedrampPackageSchemas.document_types.filter_map do |type|
      required = Array(FedrampPackageSchemas.fetch(type).document["required"])
      [ type, required.size ] if required.any? && (required - data.keys).empty?
    end
    return nil if candidates.empty?

    best = candidates.map(&:last).max
    winners = candidates.select { |_, n| n == best }
    winners.size == 1 ? winners.first.first : nil
  end

  def oscal_root_keys
    OscalSchemaValidationService::SCHEMA_MAP.values.map { |c| c[:root_key] }
  end

  def validate_oscal_json(data)
    raise Error, "An OSCAL document is a JSON object" unless data.is_a?(Hash)

    model, config = OscalSchemaValidationService::SCHEMA_MAP.find { |_, c| data.key?(c[:root_key]) }
    raise Error, "No OSCAL root element found. Expected one of: #{oscal_root_keys.join(', ')}" unless model

    declared = data.dig(config[:root_key], "metadata", "oscal-version")
    validator = OscalSchemaValidationService.new(model, version: declared)
    schema_result = validator.validate(data)
    errors = schema_result.errors.first(MAX_ERRORS).map { |msg| finding("schema", msg[/\A(\S*):/, 1], msg) }
    completeness = SchemaCompleteness.new(validator.schema_document).check(data)

    result(format: "oscal", document_type: model.to_s,
           schema: { name: config[:file], version: schema_result.schema_version, declared_version: declared },
           errors: errors + completeness.errors.map { |f| finding("completeness", f.pointer, f.message) },
           completeness: completeness)
  end

  # HDF is checked by the pinned hdf CLI against hdf-libs' own schemas. A v2
  # document (profiles[]) is checked as v2, so a valid legacy file is not
  # reported invalid for being legacy.
  def validate_hdf(data)
    type = @document_type.presence || "results"
    legacy = (data.is_a?(Array) ? data.first : data).is_a?(Hash) && (data.is_a?(Array) ? data.first : data).key?("profiles")
    docs = data.is_a?(Array) ? data : [ data ]
    runner = HdfRunner.new
    errors = docs.each_with_index.filter_map do |doc, i|
      runner.validate(StringIO.new(JSON.generate(doc)), type: type, schema_ver: legacy ? 2 : nil)
      nil
    rescue HdfRunner::Error => e
      pointer = docs.size > 1 ? "/#{i}" : ""
      finding("schema", pointer, e.message.to_s[0, 2_000])
    end

    result(format: "hdf", document_type: type,
           schema: { name: "hdf-libs #{type}", version: legacy ? "2" : "3", validator: "hdf #{hdf_version(runner)}" },
           errors: errors)
  end

  def hdf_version(runner)
    runner.version.to_s.lines.first.to_s.strip.delete_prefix("hdf version ")
  rescue StandardError
    "unknown"
  end

  # ── XML: XCCDF, OSCAL ──────────────────────────────────────────────

  def validate_xml
    doc = XmlSecurity.parse(@raw)
    namespace = doc.root&.namespace&.href
    format = @format || (namespace == XccdfSchema::NAMESPACE ? "xccdf" : nil) ||
             (namespace == OSCAL_XML_NAMESPACE ? "oscal" : nil)

    case format
    when "xccdf"
      unless namespace == XccdfSchema::NAMESPACE
        raise Error, "Not an XCCDF #{XccdfSchema::VERSION} document (root namespace #{namespace.inspect})"
      end

      errors = XccdfSchema.validate(doc).first(MAX_ERRORS).map { |msg| finding("schema", nil, msg) }
      result(format: "xccdf", document_type: doc.root.name,
             schema: { name: XccdfSchema::ROOT_FILE, version: XccdfSchema::VERSION, sha256: XccdfSchema.sha256 },
             errors: errors)
    when "oscal"
      validate_oscal_xml(doc)
    else
      raise Error, "Could not tell which format this XML document is (root namespace #{namespace.inspect})"
    end
  rescue Nokogiri::XML::SyntaxError => e
    raise Error, "Not well-formed XML: #{e.message.strip}"
  end

  def validate_oscal_xml(doc)
    model = OscalSchemaValidationService::SCHEMA_MAP.find { |_, c| c[:root_key] == doc.root.name }&.first
    raise Error, "No OSCAL root element found (got #{doc.root.name})" unless model

    r = OscalSchemaValidationService.validate_xml(model, @raw)
    result(format: "oscal", document_type: model.to_s,
           schema: { name: OscalSchemaValidationService::XSD_SCHEMA_MAP[model], version: r.schema_version,
                     declared_version: r.declared_version },
           errors: r.errors.first(MAX_ERRORS).map { |msg| finding("schema", nil, msg) })
  end

  # ── Result ─────────────────────────────────────────────────────────

  def finding(check, pointer, message)
    { check: check, pointer: pointer.to_s, message: message.to_s }
  end

  def result(format:, document_type:, schema:, errors:, completeness: nil)
    Result.new(format: format, document_type: document_type, schema: schema,
               errors: errors.first(MAX_ERRORS),
               warnings: completeness ? completeness.warnings.map(&:to_h) : [],
               warnings_total: completeness ? completeness.warnings_total : 0)
  end
end
