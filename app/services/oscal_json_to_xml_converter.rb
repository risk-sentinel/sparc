# Converts an OSCAL JSON/Ruby-hash document to properly namespaced OSCAL XML.
#
# Uses Nokogiri::XML::Builder to produce XML with the standard OSCAL namespace.
# Handles the OSCAL convention where certain keys become XML attributes (uuid,
# id, href, type, etc.) while all others become child elements.
#
# Usage:
#   data = JSON.parse(json_string)
#   xml  = OscalJsonToXmlConverter.new(:ssp, data).convert
#   # => '<?xml version="1.0" encoding="UTF-8"?>\n<system-security-plan xmlns="..."...'
#
class OscalJsonToXmlConverter
  OSCAL_NS = "http://csrc.nist.gov/ns/oscal/1.0".freeze

  ROOT_ELEMENTS = {
    ssp:                  "system-security-plan",
    assessment_results:   "assessment-results",
    assessment_plan:      "assessment-plan",
    component_definition: "component-definition",
    poam:                 "plan-of-action-and-milestones",
    profile:              "profile",
    catalog:              "catalog",
    mapping:              "mapping-collection"
  }.freeze

  # Keys that become XML attributes on their parent element per OSCAL convention.
  # All other keys become child elements.
  ATTRIBUTE_KEYS = Set.new(%w[
    uuid id href rel type name value ns class
    role-id component-uuid control-id param-id statement-id
    state identifier-type system media-type
    target-id provided-uuid responsibility-uuid
    objective-id
  ]).freeze

  def initialize(model_type, data)
    @model_type = model_type.to_sym
    @data = data
    @root_key = ROOT_ELEMENTS.fetch(@model_type) do
      raise ArgumentError, "Unknown OSCAL model type: #{model_type}. Available: #{ROOT_ELEMENTS.keys.join(', ')}"
    end
  end

  # Convert the data hash to an XML string.
  #
  # @return [String] well-formed OSCAL XML
  def convert
    root_data = @data[@root_key]
    raise ArgumentError, "Missing root key '#{@root_key}' in data" unless root_data.is_a?(Hash)

    builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
      attrs = extract_attributes(root_data).merge("xmlns" => OSCAL_NS)
      xml.send(safe_element_name(@root_key), attrs) do
        hash_children_to_xml(xml, root_data)
      end
    end

    builder.to_xml
  end

  private

  # Extract attribute-eligible key/value pairs from a hash.
  def extract_attributes(hash)
    attrs = {}
    hash.each do |key, value|
      attrs[key] = value.to_s if ATTRIBUTE_KEYS.include?(key) && scalar?(value)
    end
    attrs
  end

  # Render only the non-attribute children of a hash.
  def hash_children_to_xml(xml, hash)
    hash.each do |key, value|
      next if ATTRIBUTE_KEYS.include?(key) && scalar?(value)
      value_to_xml(xml, key, value)
    end
  end

  # Dispatch based on value type.
  def value_to_xml(xml, key, value)
    case value
    when Hash
      attrs = extract_attributes(value)
      if value.keys.all? { |k| ATTRIBUTE_KEYS.include?(k) && scalar?(value[k]) }
        # All children are attributes — self-closing element
        xml.send(safe_element_name(key), attrs)
      else
        xml.send(safe_element_name(key), attrs) do
          hash_children_to_xml(xml, value)
        end
      end
    when Array
      value.each { |item| value_to_xml(xml, singularize_key(key, item), item) }
    when String
      if key == "description" || key == "remarks" || contains_markup?(value)
        # OSCAL markup-multiline: wrap text in <p> elements
        xml.send(safe_element_name(key)) do
          value.split("\n").reject(&:blank?).each do |para|
            xml.p para.strip
          end
        end
      else
        xml.send(safe_element_name(key), value)
      end
    when Numeric, TrueClass, FalseClass
      xml.send(safe_element_name(key), value.to_s)
    when NilClass
      # Skip nil values
    else
      nil # non-JSON value types produce no element
    end
  end

  # OSCAL JSON arrays use plural keys, but XML repeats the singular element.
  # Handle known OSCAL plurals; fallback to the key as-is.
  PLURAL_TO_SINGULAR = {
    "roles"                     => "role",
    "parties"                   => "party",
    "party-uuids"               => "party-uuid",
    "props"                     => "prop",
    "links"                     => "link",
    "resources"                 => "resource",
    "rlinks"                    => "rlink",
    "responsible-parties"       => "responsible-party",
    "system-ids"                => "system-id",
    "information-types"         => "information-type",
    "categorizations"           => "categorization",
    "information-type-ids"      => "information-type-id",
    "users"                     => "user",
    "components"                => "component",
    "leveraged-authorizations"  => "leveraged-authorization",
    "inventory-items"           => "inventory-item",
    "implemented-requirements"  => "implemented-requirement",
    "implemented-components"    => "implemented-component",
    "by-components"             => "by-component",
    "statements"                => "statement",
    "set-parameters"            => "set-parameter",
    "values"                    => "value",
    "responsible-roles"         => "responsible-role",
    "role-ids"                  => "role-id",
    "authorized-privileges"     => "authorized-privilege",
    "functions-performed"       => "function-performed",
    "port-ranges"               => "port-range",
    "protocols"                 => "protocol",
    "provided"                  => "provided",
    "responsibilities"          => "responsibility",
    "inherited"                 => "inherited",
    "satisfied"                 => "satisfied",
    "control-selections"        => "control-selection",
    "include-controls"          => "include-control",
    "exclude-controls"          => "exclude-control",
    "include-objectives"        => "include-objective",
    "activities"                => "activity",
    "steps"                     => "step",
    "observations"              => "observation",
    "findings"                  => "finding",
    "risks"                     => "risk",
    "results"                   => "result",
    "related-observations"      => "related-observation",
    "related-risks"             => "related-risk",
    "origins"                   => "origin",
    "actors"                    => "actor",
    "tasks"                     => "task",
    "subjects"                  => "subject",
    "evidence"                  => "evidence",
    "relevant-evidence"         => "relevant-evidence",
    "member-of-organizations"   => "member-of-organization",
    "document-ids"              => "document-id",
    "revisions"                 => "revision",
    "controls"                  => "control",
    "groups"                    => "group",
    "parts"                     => "part",
    "params"                    => "param",
    "guidelines"                => "guideline",
    "constraints"               => "constraint",
    "tests"                     => "test",
    "select"                    => "select",
    "choice"                    => "choice",
    "imports"                   => "import",
    "include-all"               => "include-all",
    "with-ids"                  => "with-id",
    "matching"                  => "matching",
    "adds"                      => "add",
    "removes"                   => "remove",
    "alters"                    => "alter",
    "assessment-platforms"      => "assessment-platform",
    "uses-components"           => "uses-component",
    "assessment-subjects"       => "assessment-subject",
    "control-objective-selections" => "control-objective-selection",
    "poam-items"                => "poam-item",
    "related-findings"          => "related-finding",
    "remediations"              => "remediation",
    "required-assets"           => "required-asset",
    "milestones"                => "milestone",
    "maps"                      => "map",
    "sources"                   => "source",
    "targets"                   => "target",
    "mappings"                  => "mapping"
  }.freeze

  def singularize_key(key, _item)
    PLURAL_TO_SINGULAR[key] || key
  end

  # Ensure element names are valid for Nokogiri builder
  def safe_element_name(name)
    # Nokogiri treats method names with special chars via send, but
    # OSCAL element names are already valid XML element names
    name
  end

  def scalar?(value)
    value.is_a?(String) || value.is_a?(Numeric) || value.is_a?(TrueClass) || value.is_a?(FalseClass)
  end

  def contains_markup?(str)
    str.include?("\n") && str.length > 100
  end
end
