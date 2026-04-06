# Stores OSCAL JSON schemas in the database for version-aware validation.
#
# Each record represents a single NIST OSCAL schema for a specific
# document type and version. Both the original NIST schema (raw_schema)
# and the preprocessed version (preprocessed_schema) are stored.
#
# The raw schema preserves audit provenance — its SHA256 checksum can be
# verified against NIST's published schema. The preprocessed schema has
# anchor-style $refs rewritten to JSON Pointer format for json_schemer.
#
# NIST SA-10: Developer Configuration Management
class OscalSchema < ApplicationRecord
  SUPPORTED_VERSIONS = %w[1.1.1 1.1.2 1.1.3 1.2.0 1.2.1].freeze
  DEFAULT_VERSION    = "1.1.2"

  # Versions where mapping schemas exist (introduced in 1.2.0)
  MAPPING_VERSIONS = %w[1.2.0 1.2.1].freeze

  # Maps OSCAL document types to their NIST schema filename component and root key.
  # document_type uses OSCAL naming (hyphenated), not SPARC internal symbols.
  DOCUMENT_TYPE_MAP = {
    "catalog"              => { file: "oscal_catalog_schema.json",            root_key: "catalog" },
    "profile"              => { file: "oscal_profile_schema.json",            root_key: "profile" },
    "component-definition" => { file: "oscal_component-definition_schema.json", root_key: "component-definition" },
    "ssp"                  => { file: "oscal_ssp_schema.json",               root_key: "system-security-plan" },
    "assessment-plan"      => { file: "oscal_assessment-plan_schema.json",    root_key: "assessment-plan" },
    "assessment-results"   => { file: "oscal_assessment-results_schema.json", root_key: "assessment-results" },
    "poam"                 => { file: "oscal_poam_schema.json",              root_key: "plan-of-action-and-milestones" },
    "mapping"              => { file: "oscal_mapping_schema.json",           root_key: "mapping-collection" }
  }.freeze

  # Maps SPARC internal symbols to OSCAL document type strings
  SPARC_TYPE_MAP = {
    component_definition: "component-definition",
    ssp:                  "ssp",
    assessment_plan:      "assessment-plan",
    assessment_results:   "assessment-results",
    poam:                 "poam",
    profile:              "profile",
    catalog:              "catalog",
    mapping:              "mapping"
  }.freeze

  NIST_SCHEMA_URL_TEMPLATE = "https://raw.githubusercontent.com/usnistgov/OSCAL/v%<version>s/json/schema/%<file>s"

  validates :oscal_version, presence: true
  validates :document_type, presence: true
  validates :schema_format, presence: true
  validates :raw_schema,    presence: true
  validates :oscal_version, uniqueness: { scope: [ :document_type, :schema_format ] }

  scope :active, -> { where(active: true) }
  scope :json_schemas, -> { where(schema_format: "json") }

  # Find an active JSON schema for a given document type and version.
  # Accepts either OSCAL type string ("ssp") or SPARC symbol (:ssp).
  def self.find_schema(document_type:, oscal_version: DEFAULT_VERSION, format: "json")
    doc_type = resolve_document_type(document_type)
    active.find_by(
      document_type: doc_type,
      oscal_version: oscal_version,
      schema_format: format
    )
  end

  # Same as find_schema but raises if not found.
  def self.find_schema!(document_type:, oscal_version: DEFAULT_VERSION, format: "json")
    find_schema(document_type: document_type, oscal_version: oscal_version, format: format) ||
      raise(ActiveRecord::RecordNotFound,
            "No OSCAL schema found for #{document_type} v#{oscal_version} (#{format})")
  end

  # Resolve a SPARC symbol or OSCAL string to the canonical document type string.
  def self.resolve_document_type(type)
    return SPARC_TYPE_MAP[type.to_sym] if type.is_a?(Symbol) || SPARC_TYPE_MAP.key?(type.to_sym)
    type.to_s
  end

  # Build the NIST download URL for a schema.
  def self.nist_url(oscal_version, document_type)
    config = DOCUMENT_TYPE_MAP[document_type]
    return nil unless config

    format(NIST_SCHEMA_URL_TEMPLATE, version: oscal_version, file: config[:file])
  end

  # Lazily compute and persist the preprocessed schema.
  # The preprocessed schema has anchor-style $refs rewritten to JSON
  # Pointer format so json_schemer can resolve them locally.
  def ensure_preprocessed!
    return preprocessed_schema if preprocessed_schema.present?

    processed = self.class.preprocess_schema(raw_schema)
    update_column(:preprocessed_schema, processed) if persisted?
    self.preprocessed_schema = processed
  end

  # Compute SHA256 checksum of the raw schema JSON.
  def compute_checksum
    Digest::SHA256.hexdigest(raw_schema.to_json)
  end

  # ── Schema Preprocessing ──────────────────────────────────────
  # Extracted from OscalSchemaValidationService (lines 214-253).
  # OSCAL schemas use fragment $id anchors within definitions and
  # $ref values that point to those anchors. json_schemer resolves
  # $ref relative to the schema's top-level $id URI (NIST HTTP URL),
  # which is unreachable. This rewrites to JSON Pointer format.

  def self.preprocess_schema(schema)
    anchor_map = build_anchor_map(schema)
    rewritten  = rewrite_refs(schema, anchor_map)
    rewritten.delete("$id")
    rewritten
  end

  def self.build_anchor_map(schema)
    map = {}
    (schema["definitions"] || {}).each do |key, defn|
      next unless defn.is_a?(Hash) && defn["$id"]

      fragment = defn["$id"].delete_prefix("#")
      pointer  = "#/definitions/#{key}"
      map[fragment]      = pointer
      map["##{fragment}"] = pointer
    end
    map
  end

  def self.rewrite_refs(obj, anchor_map)
    case obj
    when Hash
      obj.each_with_object({}) do |(k, v), result|
        if k == "$ref" && v.is_a?(String) && v.start_with?("#") && !v.start_with?("#/")
          result[k] = anchor_map[v] || v
        elsif k == "$id" && v.is_a?(String) && v.start_with?("#")
          next
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
end
