# Validates OSCAL documents against the official NIST OSCAL schemas.
# Supports both JSON Schema validation (via json_schemer) and XSD validation
# (via Nokogiri) for XML documents.
#
# Usage:
#   result = OscalSchemaValidationService.validate(:component_definition, data_hash)
#   result.valid?          # => true / false
#   result.errors          # => [] or array of error strings
#   result.schema_version  # => "1.1.2"
#
#   # XML validation:
#   result = OscalSchemaValidationService.validate_xml(:ssp, xml_string)
#   OscalSchemaValidationService.validate_xml!(:ssp, xml_string)
#
class OscalSchemaValidationService
  OSCAL_VERSION = "1.1.2"

  SCHEMA_DIR     = Rails.root.join("lib", "oscal_schemas").freeze
  XSD_SCHEMA_DIR = Rails.root.join("lib", "oscal_xsd_schemas").freeze

  # Map logical model names to their schema files and expected root keys.
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
  #   Returns a Result struct.
  def self.validate(model_type, data)
    new(model_type).validate(data)
  end

  # Validate a JSON string against the named schema.
  def self.validate_json(model_type, json_string)
    data = JSON.parse(json_string)
    validate(model_type, data)
  rescue JSON::ParserError => e
    Result.new(valid?: false, errors: [ "Invalid JSON: #{e.message}" ], schema_version: OSCAL_VERSION)
  end

  # Convenience: validate and raise on failure (for use in export pipelines).
  def self.validate!(model_type, data)
    result = validate(model_type, data)
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
        schema_version: OSCAL_VERSION)
    end

    xsd_path = XSD_SCHEMA_DIR.join(xsd_file)
    unless File.exist?(xsd_path)
      return Result.new(valid?: false,
        errors: [ "XSD schema file not found: #{xsd_path}" ],
        schema_version: OSCAL_VERSION)
    end

    xsd_schema = xsd_schema_cache[model_type.to_sym] ||= Nokogiri::XML::Schema(File.read(xsd_path))
    doc = Nokogiri::XML(xml_string) { |config| config.noblanks }

    validation_errors = xsd_schema.validate(doc)
    error_messages = validation_errors.first(50).map { |err| err.message }

    Result.new(
      valid?: error_messages.empty?,
      errors: error_messages,
      schema_version: OSCAL_VERSION
    )
  rescue Nokogiri::XML::SyntaxError => e
    Result.new(valid?: false, errors: [ "Invalid XML: #{e.message}" ], schema_version: OSCAL_VERSION)
  rescue StandardError => e
    Result.new(valid?: false, errors: [ "XSD validation error: #{e.message}" ], schema_version: OSCAL_VERSION)
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

  # ── Instance ───────────────────────────────────────────────────────

  def initialize(model_type)
    @model_type = model_type.to_sym
    @config = SCHEMA_MAP.fetch(@model_type) do
      raise ArgumentError, "Unknown OSCAL model type: #{model_type}. Available: #{SCHEMA_MAP.keys.join(', ')}"
    end
  end

  def validate(data)
    # Structural pre-check: ensure root key is present.
    root_key = @config[:root_key]
    unless data.is_a?(Hash) && data.key?(root_key)
      return Result.new(
        valid?: false,
        errors: [ "Missing required root key '#{root_key}'. Found: #{data.is_a?(Hash) ? data.keys.join(', ') : data.class}" ],
        schema_version: OSCAL_VERSION
      )
    end

    schema = load_schema
    schemer = JSONSchemer.schema(schema)
    validation_errors = schemer.validate(data)

    error_messages = validation_errors.first(50).map { |err| format_error(err) }

    Result.new(
      valid?: error_messages.empty?,
      errors: error_messages,
      schema_version: OSCAL_VERSION
    )
  rescue StandardError => e
    Result.new(valid?: false, errors: [ "Schema validation error: #{e.message}" ], schema_version: OSCAL_VERSION)
  end

  private

  def load_schema
    self.class.schema_cache[@model_type] ||= begin
      schema_path = SCHEMA_DIR.join(@config[:file])
      raise "OSCAL schema file not found: #{schema_path}" unless File.exist?(schema_path)

      raw = JSON.parse(File.read(schema_path))
      preprocess_schema(raw)
    end
  end

  def self.schema_cache
    @schema_cache ||= {}
  end

  def self.xsd_schema_cache
    @xsd_schema_cache ||= {}
  end

  # OSCAL schemas use fragment $id anchors within definitions (e.g.,
  # $id: "#assembly_oscal-component-definition_component-definition") and
  # $ref values that point to those anchors.  json_schemer resolves $ref
  # relative to the schema's top-level $id URI, which causes UnknownRef
  # errors because the NIST HTTP URI is unreachable.
  #
  # This method rewrites anchor-style $refs to standard JSON Pointer
  # format (#/definitions/X) so json_schemer can resolve them locally.
  def preprocess_schema(schema)
    anchor_map = build_anchor_map(schema)
    rewritten  = rewrite_refs(schema, anchor_map)
    rewritten.delete("$id") # Remove top-level HTTP $id
    rewritten
  end

  # Build a map from $id fragment → JSON Pointer path for every definition.
  def build_anchor_map(schema)
    map = {}
    (schema["definitions"] || {}).each do |key, defn|
      next unless defn.is_a?(Hash) && defn["$id"]

      fragment = defn["$id"].delete_prefix("#")
      pointer  = "#/definitions/#{key}"
      map[fragment]    = pointer
      map["##{fragment}"] = pointer
    end
    map
  end

  # Recursively rewrite $ref anchor values to JSON Pointer paths and
  # strip fragment $id values from definitions.
  def rewrite_refs(obj, anchor_map)
    case obj
    when Hash
      obj.each_with_object({}) do |(k, v), result|
        if k == "$ref" && v.is_a?(String) && v.start_with?("#") && !v.start_with?("#/")
          result[k] = anchor_map[v] || v
        elsif k == "$id" && v.is_a?(String) && v.start_with?("#")
          next # Strip fragment $id values from definitions
        else
          result[k] = rewrite_refs(v, anchor_map)
        end
      end
    when Array
      obj.map { |v| rewrite_refs(v, anchor_map) }
    else
      obj
    end
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
