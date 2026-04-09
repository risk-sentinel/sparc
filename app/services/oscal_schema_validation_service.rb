# Validates OSCAL documents against the official NIST OSCAL schemas.
# Supports both JSON Schema validation (via json_schemer) and XSD validation
# (via Nokogiri) for XML documents.
#
# Schemas are loaded from the oscal_schemas database table with version
# matching. Falls back to disk files if the DB schema is not available.
#
# Usage:
#   result = OscalSchemaValidationService.validate(:component_definition, data_hash)
#   result = OscalSchemaValidationService.validate(:ssp, data_hash, version: "1.1.3")
#   result.valid?          # => true / false
#   result.errors          # => [] or array of error strings
#   result.schema_version  # => "1.1.3"
#
#   # XML validation:
#   result = OscalSchemaValidationService.validate_xml(:ssp, xml_string)
#   OscalSchemaValidationService.validate_xml!(:ssp, xml_string)
#
class OscalSchemaValidationService
  DEFAULT_OSCAL_VERSION = OscalSchema::DEFAULT_VERSION

  # Backward compatibility alias
  OSCAL_VERSION = DEFAULT_OSCAL_VERSION

  SCHEMA_DIR     = Rails.root.join("lib", "oscal_schemas").freeze
  XSD_SCHEMA_DIR = Rails.root.join("lib", "oscal_xsd_schemas").freeze

  # Map logical model names to their disk schema files and expected root keys.
  # Used as fallback when DB schemas are not available.
  SCHEMA_MAP = {
    component_definition: {
      file: "oscal_component_schema.json",
      root_key: "component-definition"
    },
    ssp: {
      file: "oscal_ssp_schema.json",
      root_key: "system-security-plan"
    },
    assessment_plan: {
      file: "oscal_assessment-plan_schema.json",
      root_key: "assessment-plan"
    },
    assessment_results: {
      file: "oscal_assessment-results_schema.json",
      root_key: "assessment-results"
    },
    poam: {
      file: "oscal_poam_schema.json",
      root_key: "plan-of-action-and-milestones"
    },
    profile: {
      file: "oscal_profile_schema.json",
      root_key: "profile"
    },
    catalog: {
      file: "oscal_catalog_schema.json",
      root_key: "catalog"
    },
    mapping: {
      file: "oscal_mapping_schema.json",
      root_key: "mapping-collection"
    }
  }.freeze

  # Map logical model names to their XSD schema files.
  XSD_SCHEMA_MAP = {
    component_definition: "oscal_component_schema.xsd",
    ssp:                  "oscal_ssp_schema.xsd",
    assessment_plan:      "oscal_assessment-plan_schema.xsd",
    assessment_results:   "oscal_assessment-results_schema.xsd",
    poam:                 "oscal_poam_schema.xsd",
    profile:              "oscal_profile_schema.xsd",
    catalog:              "oscal_catalog_schema.xsd"
  }.freeze

  Result = Struct.new(:valid?, :errors, :schema_version, keyword_init: true)

  # ── Class API ──────────────────────────────────────────────────────

  # Validate a Ruby hash (already parsed JSON) against the named schema.
  #   model_type  — one of SCHEMA_MAP keys, e.g. :component_definition
  #   data        — the Ruby hash to validate
  #   version:    — OSCAL version to validate against (default: 1.1.2)
  #   Returns a Result struct.
  def self.validate(model_type, data, version: nil)
    new(model_type, version: version).validate(data)
  end

  # Validate a JSON string against the named schema.
  def self.validate_json(model_type, json_string, version: nil)
    data = JSON.parse(json_string)
    validate(model_type, data, version: version)
  rescue JSON::ParserError => e
    Result.new(valid?: false, errors: [ "Invalid JSON: #{e.message}" ], schema_version: version || DEFAULT_OSCAL_VERSION)
  end

  # Convenience: validate and raise on failure (for use in export pipelines).
  def self.validate!(model_type, data, version: nil)
    result = validate(model_type, data, version: version)
    unless result.valid?
      raise OscalValidationError, "OSCAL #{model_type} validation failed:\n#{result.errors.join("\n")}"
    end
    result
  end

  # Validate an XML string against the named XSD schema.
  #   model_type  — one of XSD_SCHEMA_MAP keys, e.g. :ssp
  #   xml_string  — the raw XML string to validate
  #   Returns a Result struct.
  def self.validate_xml(model_type, xml_string)
    xsd_file = XSD_SCHEMA_MAP.fetch(model_type.to_sym) do
      return Result.new(valid?: false,
        errors: [ "No XSD schema available for model type: #{model_type}" ],
        schema_version: DEFAULT_OSCAL_VERSION)
    end

    xsd_path = XSD_SCHEMA_DIR.join(xsd_file)
    unless File.exist?(xsd_path)
      return Result.new(valid?: false,
        errors: [ "XSD schema file not found: #{xsd_path}" ],
        schema_version: DEFAULT_OSCAL_VERSION)
    end

    xsd_schema = xsd_schema_cache[model_type.to_sym] ||= Nokogiri::XML::Schema(File.read(xsd_path))
    doc = Nokogiri::XML(xml_string) { |config| config.noblanks }

    validation_errors = xsd_schema.validate(doc)
    error_messages = validation_errors.first(50).map { |err| err.message }

    Result.new(
      valid?: error_messages.empty?,
      errors: error_messages,
      schema_version: DEFAULT_OSCAL_VERSION
    )
  rescue Nokogiri::XML::SyntaxError => e
    Result.new(valid?: false, errors: [ "Invalid XML: #{e.message}" ], schema_version: DEFAULT_OSCAL_VERSION)
  rescue StandardError => e
    Result.new(valid?: false, errors: [ "XSD validation error: #{e.message}" ], schema_version: DEFAULT_OSCAL_VERSION)
  end

  # Validate XML and raise on failure (for use in export pipelines).
  def self.validate_xml!(model_type, xml_string)
    result = validate_xml(model_type, xml_string)
    unless result.valid?
      raise OscalValidationError, "OSCAL #{model_type} XML validation failed:\n#{result.errors.join("\n")}"
    end
    result
  end

  # List available schema types.
  def self.available_schemas
    SCHEMA_MAP.keys
  end

  # List available XSD schema types.
  def self.available_xsd_schemas
    XSD_SCHEMA_MAP.keys
  end

  # Clear the in-memory schema cache (e.g., after rake task updates DB schemas).
  def self.clear_cache!
    @schema_cache = {}
  end

  # ── Instance ───────────────────────────────────────────────────────

  def initialize(model_type, version: nil)
    @model_type = model_type.to_sym
    @version = version.presence || DEFAULT_OSCAL_VERSION
    @config = SCHEMA_MAP.fetch(@model_type) do
      raise ArgumentError, "Unknown OSCAL model type: #{model_type}. Available: #{SCHEMA_MAP.keys.join(', ')}"
    end
  end

  def validate(data)
    root_key = @config[:root_key]
    unless data.is_a?(Hash) && data.key?(root_key)
      return Result.new(
        valid?: false,
        errors: [ "Missing required root key '#{root_key}'. Found: #{data.is_a?(Hash) ? data.keys.join(', ') : data.class}" ],
        schema_version: @version
      )
    end

    schema = load_schema
    schemer = JSONSchemer.schema(schema)
    validation_errors = schemer.validate(data)

    error_messages = validation_errors.first(50).map { |err| format_error(err) }

    Result.new(
      valid?: error_messages.empty?,
      errors: error_messages,
      schema_version: @version
    )
  rescue StandardError => e
    Result.new(valid?: false, errors: [ "Schema validation error: #{e.message}" ], schema_version: @version)
  end

  private

  # Load schema with fallback chain:
  #   1. DB schema for requested version
  #   2. DB schema for DEFAULT_OSCAL_VERSION (with warning)
  #   3. Disk file (with warning)
  def load_schema
    cache_key = [ @model_type, @version ]
    self.class.schema_cache[cache_key] ||= load_schema_from_db || load_schema_from_disk
  end

  def load_schema_from_db
    # Try requested version
    db_schema = OscalSchema.find_schema(document_type: @model_type, oscal_version: @version)

    # Fallback to default version if requested version not found
    if db_schema.nil? && @version != DEFAULT_OSCAL_VERSION
      Rails.logger.warn("[OscalSchemaValidation] No DB schema for #{@model_type} v#{@version}, trying v#{DEFAULT_OSCAL_VERSION}")
      db_schema = OscalSchema.find_schema(document_type: @model_type, oscal_version: DEFAULT_OSCAL_VERSION)
      @version = DEFAULT_OSCAL_VERSION if db_schema
    end

    return nil unless db_schema

    db_schema.ensure_preprocessed!
  rescue ActiveRecord::StatementInvalid
    # Table may not exist yet (e.g., during migration or CI without DB setup)
    nil
  end

  def load_schema_from_disk
    Rails.logger.warn("[OscalSchemaValidation] Falling back to disk schema for #{@model_type}")
    schema_path = SCHEMA_DIR.join(@config[:file])
    raise "OSCAL schema file not found: #{schema_path}" unless File.exist?(schema_path)

    raw = JSON.parse(File.read(schema_path))
    OscalSchema.preprocess_schema(raw)
  end

  def self.schema_cache
    @schema_cache ||= {}
  end

  def self.xsd_schema_cache
    @xsd_schema_cache ||= {}
  end

  def format_error(error)
    path = error["data_pointer"].presence || "(root)"
    type = error["type"]
    details = error["details"] || {}

    case type
    when "required"
      missing = details["missing_keys"]&.join(", ") || "unknown"
      "#{path}: missing required properties: #{missing}"
    when "enum"
      "#{path}: value not in allowed list"
    when "type"
      "#{path}: expected #{details['expected_type'] || 'unknown type'}"
    when "pattern"
      "#{path}: does not match pattern #{details['pattern']}"
    when "format"
      "#{path}: invalid format '#{details['format']}'"
    else
      msg = error["error"] || error.to_s
      "#{path}: #{msg}"
    end
  end
end

# Custom error class for use with validate!
class OscalValidationError < StandardError; end
