# frozen_string_literal: true

# CatalogIntegrityService — content checks on an OSCAL catalog that neither the
# schema nor OscalConformanceService can make (#1228).
#
# NIST shipped SP 800-53 Rev 5.2.0 with errors that are perfectly valid OSCAL:
# every part and prop name is NIST-defined and every link resolves. They are
# wrong only in what they SAY:
#
#   1. label-names-own-control — a part's `label` prop must name the control
#      the part belongs to. SA-15(13)'s Examine method was labelled
#      `SA-15(12)-Examine` (usnistgov/oscal-content#343).
#   2. assessment-for-own-statement — an `assessment-for` link on an
#      assessment-objective or assessment-method part must point into its own
#      control's statement. Six SA-24 objectives pointed at AC-2's statement
#      (`#ac-2_smt.a.5`, `#ac-2_smt.b`), a target that exists and so passes
#      plain link resolution (usnistgov/oscal-content#301).
#
# Input is the parsed catalog JSON (root key included, or the `catalog` object).
# The checks read; they never change the catalog. An error NIST has not found
# yet is reported upstream, not patched here.
#
# `bin/rails catalog:integrity[path]` runs both over a catalog file.
#
# NIST 800-53: SI-10 (input validation of catalog content), CA-2 (an assessment
# objective must assess its own control). See: docs/compliance/nist-sp800-53-rev5-mapping.md
class CatalogIntegrityService
  Finding = Struct.new(:rule, :control_id, :part_id, :message, keyword_init: true) do
    def to_s = "#{rule}  #{control_id}  #{part_id}  #{message}"
  end

  ASSESSMENT_PART_NAMES = %w[assessment-objective assessment-method].freeze

  # The leading control label of a part label: `SA-15(12)` in
  # `SA-15(12)-Examine`, `SA-24` in `SA-24b.[10]`, `SI-02(07)` in
  # `SI-02(07)c.[01]`. A label with no such prefix (`a.`, `(a)`) names no
  # control, so it has nothing to agree or disagree with.
  CONTROL_LABEL = /\A([A-Z]{2,3})-(\d+)(?:\((\d+)\))?(?![\d(])/

  def self.check(catalog)
    new(catalog).check
  end

  def initialize(catalog)
    catalog = JSON.parse(catalog) if catalog.is_a?(String)
    @catalog = catalog.key?("catalog") ? catalog["catalog"] : catalog
  end

  def check
    findings = []
    each_control(@catalog) do |control|
      findings.concat(check_labels(control))
      findings.concat(check_assessment_for(control))
    end
    findings
  end

  # The control id a label names, in OSCAL id form (`SA-15(12)` → `sa-15.12`,
  # `SI-02(07)` → `si-2.7`), or nil when the label names no control.
  def self.control_id_for_label(label)
    match = CONTROL_LABEL.match(label.to_s)
    return nil unless match

    base = "#{match[1].downcase}-#{match[2].to_i}"
    match[3] ? "#{base}.#{match[3].to_i}" : base
  end

  private

  def each_control(node, &block)
    Array(node["groups"]).each { |group| each_control(group, &block) }
    Array(node["controls"]).each do |control|
      yield control
      each_control(control, &block)
    end
  end

  # Every part of a control, at any depth (but not its child controls' parts).
  def each_part(parts, &block)
    Array(parts).each do |part|
      yield part
      each_part(part["parts"], &block)
    end
  end

  def check_labels(control)
    own = control["id"]
    findings = []
    each_part(control["parts"]) do |part|
      Array(part["props"]).each do |prop|
        next unless prop["name"] == "label" && plain_ns?(prop)

        named = self.class.control_id_for_label(prop["value"])
        next if named.nil? || named == own

        findings << Finding.new(
          rule: "label-names-own-control", control_id: own, part_id: part["id"],
          message: "label #{prop['value'].inspect} names #{named}, not #{own}"
        )
      end
    end
    findings
  end

  def check_assessment_for(control)
    own = control["id"]
    statement_ids = statement_part_ids(control)
    findings = []
    each_part(control["parts"]) do |part|
      next unless ASSESSMENT_PART_NAMES.include?(part["name"])

      Array(part["links"]).each do |link|
        next unless link["rel"] == "assessment-for"

        target = link["href"].to_s.delete_prefix("#")
        next if statement_ids.include?(target)

        findings << Finding.new(
          rule: "assessment-for-own-statement", control_id: own, part_id: part["id"],
          message: "assessment-for #{link['href'].inspect} is not in #{own}'s statement"
        )
      end
    end
    findings
  end

  def statement_part_ids(control)
    ids = Set.new
    Array(control["parts"]).select { |p| p["name"] == "statement" }.each do |statement|
      each_part([ statement ]) { |part| ids << part["id"] if part["id"] }
    end
    ids
  end

  # A label in someone else's namespace is theirs to define.
  def plain_ns?(prop)
    OscalNamespace.nist?(prop["ns"])
  end
end
