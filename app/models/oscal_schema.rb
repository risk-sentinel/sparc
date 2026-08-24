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
  # #1020 — 1.2.2 added 2026-08-21. A version SPARC does not carry is a version
  # it cannot validate against, and 1.2.x tightens real constraints: it applies
  # the non-empty-string datatype to `metadata.title` and other title fields
  # that 1.1.x left unconstrained. An exporter that satisfies 1.1.2 does not
  # automatically satisfy 1.2.x, and finding that out from an assessor would be
  # finding out too late.
  SUPPORTED_VERSIONS = %w[1.1.1 1.1.2 1.1.3 1.2.0 1.2.1 1.2.2].freeze

  # What SPARC EMITS. #1020 added 1.2.2 to validate against and deliberately
  # left this at 1.1.2, because adding a version to check is a different
  # decision from changing the version we write.
  #
  # Owner-decided 2026-08-23: make 1.2.2 the default. The evidence for the move
  # is that it changes nothing about which documents are exportable — every
  # export type was validated against BOTH versions across every record in the
  # instance (catalog, profile, ssp, component-definition, assessment-plan,
  # assessment-results, poam) and the pass/fail set is identical: no document
  # passes 1.1.2 and fails 1.2.2. The tightening 1.2.x introduces (non-empty
  # `metadata.title` and sibling title fields) is already satisfied, because
  # those titles are required by SPARC's own model validations.
  #
  # A document that carries its own `oscal_version` still wins — this is the
  # fallback for documents that do not state one, and the version SPARC
  # declares in `metadata.oscal-version` when it authors a document.
  DEFAULT_VERSION    = "1.2.2"

  # OSCAL document-type strings reused as map keys + root_keys below.
  COMPONENT_DEFINITION = "component-definition".freeze
  ASSESSMENT_PLAN      = "assessment-plan".freeze
  ASSESSMENT_RESULTS   = "assessment-results".freeze

  # Versions where mapping schemas exist (introduced in 1.2.0)
  MAPPING_VERSIONS = %w[1.2.0 1.2.1 1.2.2].freeze

  # #1020 — OSCAL 1.2.0 rejects documents that 1.1.x, 1.2.1 and 1.2.2 all accept,
  # and the fault is in that release's schema rather than in the documents.
  #
  # 1.2.0 omits the `associated-risk` definition entirely, so `risk-uuid` inside
  # `related-risks` has nothing to match while `additionalProperties: false`
  # makes it a violation. 1.2.1 restores it as
  # `oscal-poam-oscal-assessment-common:associated-risk`
  # (`properties: [remarks, risk-uuid]`, `required: [risk-uuid]`), and 1.2.2 is
  # identical.
  #
  # Confirmed against two unrelated producers: SPARC's own POA&M and SAR
  # exporters, and hdf-cli's converter. Both emit `risk-uuid`; only 1.2.0
  # objects. Validating against 1.2.0 therefore reports failures that are not
  # the document's fault, which is worth knowing before anyone chases one.
  KNOWN_DEFECTIVE_VERSIONS = { "1.2.0" => "omits the associated-risk definition; " \
                                          "`related-risks[].risk-uuid` is rejected. Fixed in 1.2.1." }.freeze

  # Maps OSCAL document types to their NIST schema filename component and
  # root key. Filenames match exactly what NIST publishes as GitHub
  # release assets (verified against tags v1.1.1 / v1.1.2 / v1.1.3 /
  # v1.2.0 / v1.2.1). document_type uses OSCAL naming (hyphenated),
  # not SPARC internal symbols.
  #
  # Note: NIST emits the component-definition schema as
  # `oscal_component_schema.json` (no hyphen), even though the OSCAL
  # document_type is `component-definition`. The validator's SCHEMA_MAP
  # uses the same filename — both maps must agree.
  DOCUMENT_TYPE_MAP = {
    "catalog"              => { file: "oscal_catalog_schema.json",            root_key: "catalog" },
    "profile"              => { file: "oscal_profile_schema.json",            root_key: "profile" },
    COMPONENT_DEFINITION => { file: "oscal_component_schema.json",          root_key: COMPONENT_DEFINITION },
    "ssp"                  => { file: "oscal_ssp_schema.json",                root_key: "system-security-plan" },
    ASSESSMENT_PLAN      => { file: "oscal_assessment-plan_schema.json",    root_key: ASSESSMENT_PLAN },
    ASSESSMENT_RESULTS   => { file: "oscal_assessment-results_schema.json", root_key: ASSESSMENT_RESULTS },
    "poam"                 => { file: "oscal_poam_schema.json",               root_key: "plan-of-action-and-milestones" },
    "mapping"              => { file: "oscal_mapping_schema.json",            root_key: "mapping-collection" }
  }.freeze

  # Maps SPARC internal symbols to OSCAL document type strings
  SPARC_TYPE_MAP = {
    component_definition: COMPONENT_DEFINITION,
    ssp:                  "ssp",
    assessment_plan:      ASSESSMENT_PLAN,
    assessment_results:   ASSESSMENT_RESULTS,
    poam:                 "poam",
    profile:              "profile",
    catalog:              "catalog",
    mapping:              "mapping"
  }.freeze

  # NIST publishes schema files as GitHub release assets, not in a
  # source-tree path. Pre-#453 this template pointed at
  # `raw.githubusercontent.com/.../json/schema/...` which 404s for
  # every release tag — the seed task always silently fell through to
  # the disk fallback (single version). Fixed to use the release-asset
  # URL pattern that actually serves the schemas.
  NIST_SCHEMA_URL_TEMPLATE = "https://github.com/usnistgov/OSCAL/releases/download/v%<version>s/%<file>s"

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
