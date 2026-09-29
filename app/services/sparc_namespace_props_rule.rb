# frozen_string_literal: true

require "json_schemer"

# Checks the SPARC-namespace props in an exported OSCAL document against the
# contract sparc-horizon validates them with (#1154), so SPARC refuses to
# publish what its consumer would reject.
#
# NIST's JSON Schema cannot see any of this. A prop's `value` is a free string
# there, so `blocks-ato: "maybe"`, `fips-199: "fips-199-moderate"` or a
# `parent-uuid` that is not a uuid all pass schema validation and still break
# the federation tree, the rollup weight or the ATO ranking downstream. This is
# the same bug class #1106 found in NIST's own namespace: a constraint JSON
# Schema cannot express, reported as PASSED.
#
# ── What it checks ─────────────────────────────────────────────────────────
#
#   1. VALUES — every prop whose `ns` is SPARC's registered namespace and whose
#      name is one of the nine is validated against the vendored schema,
#      lib/data/oscal_ns/sparc-namespace-props.v1.schema.json, verbatim.
#   2. PLACEMENT — each name only where the contract puts it (Horizon's
#      docs/03-data-model.md): node-type on SSP metadata or a party; parent-uuid,
#      next-decision-date and fips-199 on SSP metadata; blocks-ato,
#      condition-expires and trigger on a risk; evidence-kind and signed-by on a
#      back-matter resource. A value in the wrong place is read by nothing, or
#      read by the wrong thing.
#   3. UNIQUENESS — one of each name per props array. Two `fips-199` values on
#      one SSP is a contradiction a consumer resolves by guessing.
#   4. PRESENCE — on an SSP, `required_metadata` names the props that must be
#      on `metadata.props` with the value given (node-type always; parent-uuid
#      when the SSP has a boundary; fips-199 when the system is categorized).
#
# ── What it deliberately does NOT check ────────────────────────────────────
#
# Props in SPARC's namespace with any OTHER name (`sparc-status`,
# `control-type`, `provided-as`, `responsible-entities`, `priority`, ...). The
# vendored schema enumerates only the nine, so it rejects every one of those —
# see spec/services/sparc_namespace_props_rule_spec.rb, which records that.
# Validating them here would refuse every SSP SPARC has ever exported. Which of
# the two vocabularies should move is an owner decision, not something an
# export gate settles by failing.
#
# Props in any other namespace are never looked at: Horizon's rule, and OSCAL's
# — an absent `ns` means NIST's.
class SparcNamespacePropsRule
  SCHEMA_PATH = Rails.root.join("lib/data/oscal_ns/sparc-namespace-props.v1.schema.json").freeze

  ROOT_KEYS = {
    ssp:                "system-security-plan",
    poam:               "plan-of-action-and-milestones",
    assessment_results: "assessment-results"
  }.freeze

  PLACEMENT = {
    "node-type"          => %i[ssp_metadata party],
    "parent-uuid"        => %i[ssp_metadata],
    "next-decision-date" => %i[ssp_metadata],
    "fips-199"           => %i[ssp_metadata],
    "blocks-ato"         => %i[risk],
    "condition-expires"  => %i[risk],
    "trigger"            => %i[risk],
    "evidence-kind"      => %i[resource],
    "signed-by"          => %i[resource]
  }.freeze

  PLACEMENT_LABELS = {
    ssp_metadata: "SSP metadata", party: "a party", risk: "a risk", resource: "a back-matter resource"
  }.freeze

  def self.schemer
    @schemer ||= JSONSchemer.schema(JSON.parse(File.read(SCHEMA_PATH)))
  end

  # Raises OscalValidationError, the error every validated export already
  # raises for a schema-invalid document, so callers need no new handling.
  def self.validate!(model, data, required_metadata: {})
    errors = new(model, data, required_metadata: required_metadata).errors
    return true if errors.empty?

    raise OscalValidationError,
          "OSCAL #{model} SPARC-namespace props (#{SparcNamespaceProps::NS}) are not conformant:\n#{errors.join("\n")}"
  end

  # The vendored schema's verdict on ONE prop, as messages. Public so the
  # finding about SPARC's other props can be reproduced rather than asserted.
  def self.schema_errors_for(prop)
    schemer.validate(prop).map { |e| e["error"] }
  end

  def initialize(model, data, required_metadata: {})
    @model = model.to_sym
    @root_key = ROOT_KEYS.fetch(@model) { raise ArgumentError, "no SPARC-namespace rule for #{model}" }
    @data = data
    @required_metadata = required_metadata
  end

  def errors
    @errors = []
    root = @data.is_a?(Hash) ? @data[@root_key] : nil
    return [ "missing root key '#{@root_key}'" ] unless root.is_a?(Hash)

    walk(root, "/#{@root_key}", [])
    check_required_metadata(root)
    @errors
  end

  private

  # `trail` is the list of keys/indices from the root to `node`, which is what
  # placement is decided from.
  def walk(node, pointer, trail)
    case node
    when Hash
      check_props(node["props"], "#{pointer}/props", placement_of(trail)) if node["props"].is_a?(Array)
      node.each { |key, child| walk(child, "#{pointer}/#{key}", trail + [ key ]) unless key == "props" }
    when Array
      node.each_with_index { |child, i| walk(child, "#{pointer}/#{i}", trail + [ i ]) }
    else
      nil # a scalar holds no props and nothing beneath it
    end
  end

  def placement_of(trail)
    return (@model == :ssp ? :ssp_metadata : :metadata) if trail == [ "metadata" ]
    return :party if trail.size == 3 && trail[0..1] == %w[metadata parties]
    return :resource if trail.size == 3 && trail[0..1] == %w[back-matter resources]
    return :risk if trail.size >= 2 && trail[-2] == "risks" && trail[-1].is_a?(Integer)

    :elsewhere
  end

  def check_props(props, pointer, placement)
    seen = Hash.new(0)
    props.each_with_index do |prop, i|
      next unless SparcNamespaceProps.ours?(prop)

      at = "#{pointer}/#{i} (#{prop['name']})"
      self.class.schema_errors_for(prop).each { |message| @errors << "#{at}: #{message}" }

      allowed = PLACEMENT.fetch(prop["name"])
      unless allowed.include?(placement)
        @errors << "#{at}: belongs on #{allowed.map { |p| PLACEMENT_LABELS[p] }.join(' or ')}, not here"
      end

      seen[prop["name"]] += 1
    end
    seen.each { |name, count| @errors << "#{pointer}: #{name} appears #{count} times" if count > 1 }
  end

  def check_required_metadata(root)
    return if @required_metadata.empty?

    props = Array(root.dig("metadata", "props")).select { |p| SparcNamespaceProps.ours?(p) }
    @required_metadata.each do |name, value|
      found = props.find { |p| p["name"] == name }
      if found.nil?
        @errors << "/#{@root_key}/metadata/props: #{name} is required and missing"
      elsif found["value"] != value
        @errors << "/#{@root_key}/metadata/props: #{name} is #{found['value'].inspect}, expected #{value.inspect}"
      end
    end
  end
end
