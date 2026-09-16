# frozen_string_literal: true

# OSCAL conformance checking (#1106).
#
# `OscalSchemaValidationService` answers "is this the right SHAPE". This answers
# "does it MEAN what a conforming reader will think it means" — the rules that
# live in NIST's Metaschema and do not survive translation to JSON Schema:
#
#   1. A prop or part with no `ns` claims NIST defined that NAME. It must have.
#   2. A prop whose name NIST defines must carry a value from NIST's vocabulary,
#      where that vocabulary is ENFORCED rather than advisory.
#   3. Every `role-id` must resolve to a role the document declares, and every
#      `party-uuid` to a declared party. Schema validation cannot see this: the
#      document is structurally perfect and still refers to nothing.
#
# The vocabularies come from `lib/oscal_conformance/<version>/`, keyed by the
# version THIS DOCUMENT declares — SPARC supports six and they differ (SAP value
# vocabularies go 32 -> 52 -> 53).
#
# ── What is deliberately NOT a violation ────────────────────────────────────
#
# Anything in the deployment's own namespace. SPARC validates claims about OTHER
# authorities' vocabularies; it does not police the operator's own. An
# organization-defined role or prop is legal OSCAL by construction — NIST sets
# `allow-other="yes"` on `responsible-role/@role-id` at every site — so the only
# hard requirement for a role is that it RESOLVES.
class OscalConformanceService
  DATASET_DIR = Rails.root.join("lib", "oscal_conformance")

  Finding = Struct.new(:severity, :rule, :location, :message, keyword_init: true)

  Result = Struct.new(:findings, :oscal_version, :model, keyword_init: true) do
    def violations = findings.select { |f| f.severity == :violation }
    def advisories = findings.select { |f| f.severity == :advisory }
    def conformant? = violations.empty?

    def summary
      return "conformant (#{advisories.size} advisory)" if conformant?

      "#{violations.size} violation(s), #{advisories.size} advisory"
    end
  end

  class << self
    def dataset_for(version)
      @dataset_cache ||= {}
      @dataset_cache[version] ||= begin
        path = DATASET_DIR.join(version.to_s, "conformance.json")
        path.exist? ? JSON.parse(path.read) : nil
      end
    end

    def reset_cache! = @dataset_cache = nil
  end

  # `document` is the parsed OSCAL hash (the full export, root key included).
  # `model` is a CONFORMANCE_MODELS key, e.g. "system-security-plan".
  def initialize(document, model:)
    @document = document.is_a?(String) ? JSON.parse(document) : document
    @model    = model
    @root     = @document[model] || @document.values.first || {}
    @findings = []
  end

  def validate
    version = declared_version
    rules   = self.class.dataset_for(version)&.dig("models", @model)

    # An unknown version is itself a finding. Silently passing would mean a
    # document declaring an unsupported version gets a clean bill of health from
    # a check that never ran — the failure shape this whole issue is about.
    if rules.nil?
      @findings << Finding.new(severity: :violation, rule: "dataset-missing", location: "metadata",
                               message: "no conformance dataset for OSCAL #{version} — " \
                                        "run bin/rails oscal:bundle_conformance[#{version}]")
      return result(version)
    end

    walk(@root, "", rules)
    check_references
    result(version)
  end

  private

  def result(version) = Result.new(findings: @findings, oscal_version: version, model: @model)

  def declared_version
    @root.dig("metadata", "oscal-version").presence || OscalSchema::DEFAULT_VERSION
  end

  def walk(node, path, rules)
    case node
    when Hash
      Array(node["props"]).each_with_index { |p, i| check_prop(p, "#{path}/props[#{i}]", rules) }
      Array(node["parts"]).each_with_index { |p, i| check_part(p, "#{path}/parts[#{i}]", rules) }
      node.each { |k, v| walk(v, "#{path}/#{k}", rules) unless %w[props parts].include?(k) }
    when Array
      node.each_with_index { |v, i| walk(v, "#{path}[#{i}]", rules) }
    else
      # A leaf scalar — string, number, boolean, nil. Nothing to descend into
      # and nothing to check: props and parts are always carried by a Hash.
      nil
    end
  end

  def check_prop(prop, path, rules)
    return unless prop.is_a?(Hash)

    name = prop["name"]
    return unless OscalNamespace.nist?(prop["ns"])

    unless rules["prop_names"].key?(name)
      @findings << Finding.new(
        severity: :violation, rule: "prop-name-not-nist", location: path,
        message: "prop #{name.inspect} carries no `ns`, which claims NIST defines it for " \
                 "#{@model}. NIST does not. Namespace it, or use a NIST name."
      )
      return
    end

    vocabulary = rules.dig("prop_values", name)
    return if vocabulary.blank? || vocabulary["values"].include?(prop["value"])

    @findings << Finding.new(
      severity: vocabulary["advisory"] ? :advisory : :violation,
      rule: "prop-value-not-in-vocabulary", location: path,
      message: "prop #{name.inspect} has value #{prop['value'].inspect}; NIST allows " \
               "#{vocabulary['values'].join(' / ')}"
    )
  end

  def check_part(part, path, rules)
    return unless part.is_a?(Hash)

    name = part["name"]
    return unless OscalNamespace.nist?(part["ns"])
    return if rules.fetch("part_names", {}).key?(name)

    @findings << Finding.new(
      severity: :violation, rule: "part-name-not-nist", location: path,
      message: "part #{name.inspect} carries no `ns`, which claims NIST defines it for " \
               "#{@model}. Parts and props are separate vocabularies; NIST defines neither this name."
    )

    Array(part["parts"]).each_with_index { |p, i| check_part(p, "#{path}/parts[#{i}]", rules) }
  end

  # Referential integrity — the half schema validation structurally cannot do.
  # A document can be perfectly shaped and refer to nothing.
  def check_references
    declared_roles     = Array(@root.dig("metadata", "roles")).filter_map { |r| r["id"] }.to_set
    declared_parties   = Array(@root.dig("metadata", "parties")).filter_map { |p| p["uuid"] }.to_set
    declared_locations = Array(@root.dig("metadata", "locations")).filter_map { |l| l["uuid"] }.to_set

    collect_references(@root, "").each do |kind, value, path|
      case kind
      when :role
        next if declared_roles.include?(value)

        @findings << Finding.new(
          severity: :violation, rule: "role-id-unresolved", location: path,
          message: "role-id #{value.inspect} resolves to no role in metadata.roles. " \
                   "A custom role is legal — NIST sets allow-other on role-id — but it must be DECLARED."
        )
      when :party
        next if declared_parties.include?(value)

        @findings << Finding.new(
          severity: :violation, rule: "party-uuid-unresolved", location: path,
          message: "party-uuid #{value.inspect} resolves to no party in metadata.parties"
        )
      when :location
        next if declared_locations.include?(value)

        @findings << Finding.new(
          severity: :violation, rule: "location-uuid-unresolved", location: path,
          message: "location-uuid #{value.inspect} resolves to no location in metadata.locations"
        )
      else
        # NOT a no-op. `collect_references` is where reference kinds are
        # produced; adding one there and forgetting it here would drop a whole
        # class of reference silently — the document would validate while its
        # references dangled, which is the exact failure this service exists to
        # catch. Fail loudly instead.
        raise ArgumentError, "unhandled reference kind #{kind.inspect} at #{path}"
      end
    end
  end

  # ── What is collected, and what deliberately is not (#1134 audit) ────────
  #
  # Every reference-shaped key in the six bundled models was enumerated from the
  # schemas. They fall into two groups.
  #
  # Resolved here, because their target lives in `metadata` — which is the half
  # of referential integrity this service owns:
  #
  #   role-id, role-ids, party-uuid, party-uuids, location-uuids
  #
  # NOT resolved here, because their target is another SECTION of the document
  # rather than metadata, and checking them means walking that section:
  #
  #   component-uuid           -> system-implementation.components
  #   activity-uuid, task-uuid -> the assessment plan's local definitions
  #   subject-uuid, subject-placeholder-uuid
  #   observation-uuid, risk-uuid, finding-uuid, response-uuid
  #   implementation-uuid, implementation-statement-uuid
  #   provided-uuid, responsibility-uuid
  #
  # `actor-uuid` is the awkward one and is deliberately left alone: OSCAL's
  # `origin/actors[]` resolves it against parties, tools OR assessment platforms
  # depending on the sibling `type`, so treating it as a party reference would
  # manufacture false violations on every tool-origin finding.
  #
  # That list is a record, not a plan. Covering it is a separate piece of work;
  # what matters is that it was measured rather than assumed.
  def collect_references(node, path, acc = [])
    case node
    when Hash
      node.each do |k, v|
        case k
        when "role-id"     then acc << [ :role, v, path ]
        # #1134 — the PLURAL was missing, so `system-implementation.users[].role-ids`
        # was never collected and never checked. `import_boundary_users` wrote the
        # raw boundary-membership role into it, underscored and undeclared, and
        # this service reported a clean document. The guard below fires on an
        # unhandled reference KIND; a missing KEY falls into the `else` and
        # returns before it can apply, which is how the gap survived.
        when "role-ids"    then Array(v).each_with_index { |r, i| acc << [ :role, r, "#{path}/role-ids[#{i}]" ] }
        when "party-uuids" then Array(v).each { |u| acc << [ :party, u, path ] }
        when "party-uuid"  then acc << [ :party, v, path ]
        when "location-uuids"
          Array(v).each_with_index { |u, i| acc << [ :location, u, "#{path}/location-uuids[#{i}]" ] }
        else
          # Every other key: not a reference. Recursion below still descends
          # into it, so nothing is missed by not matching here.
          nil
        end
        collect_references(v, "#{path}/#{k}", acc)
      end
    when Array
      node.each_with_index { |v, i| collect_references(v, "#{path}[#{i}]", acc) }
    else
      # Leaf scalar — a reference is always a Hash value under a known key.
      nil
    end
    acc
  end
end
