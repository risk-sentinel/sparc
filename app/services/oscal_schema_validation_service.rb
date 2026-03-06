# Validates OSCAL JSON documents against the official NIST OSCAL v1.1.2
# JSON schemas.  Uses the json_schemer gem for Draft 2020-12 support.
#
# Usage:
#   result = OscalSchemaValidationService.validate(:component_definition, data_hash)
#   result.valid?          # => true / false
#   result.errors          # => [] or array of error strings
#   result.schema_version  # => "1.1.2"
#
class OscalSchemaValidationService
  OSCAL_VERSION = "1.1.2"

  SCHEMA_DIR = Rails.root.join("lib", "oscal_schemas").freeze

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
    }
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

  # List available schema types.
  def self.available_schemas
    SCHEMA_MAP.keys
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
    schema_path = SCHEMA_DIR.join(@config[:file])
    raise "OSCAL schema file not found: #{schema_path}" unless File.exist?(schema_path)

    # Cache parsed schemas in a class-level hash for performance.
    self.class.schema_cache[@model_type] ||= JSON.parse(File.read(schema_path))
  end

  def self.schema_cache
    @schema_cache ||= {}
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
