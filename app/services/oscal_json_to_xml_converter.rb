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

  # XSD element-ordering table (#827).
  #
  # OSCAL JSON has no key-order requirement, but every OSCAL XML assembly is an
  # `xs:sequence` with a MANDATED child order. Emitting children in JSON
  # insertion order therefore produced XML that no OSCAL XSD would accept — for
  # example <metadata> needs title, published, last-modified, version,
  # oscal-version..., and <param> needs prop, link, label, usage... regardless
  # of how the exporter happened to build the hash.
  #
  # The order is PER PARENT, not global: `prop` is the 8th child of <metadata>
  # but the 1st of <param>, so a single name-to-rank map would be wrong. The
  # table is keyed by the parent's XSD type and carries a child-name-to-type map
  # so the walk can track its position in the schema as it descends.
  #
  # Generated from lib/oscal_xsd_schemas/ — the same XSDs
  # OscalSchemaValidationService validates against, so the ordering used to
  # write the XML cannot disagree with the ordering used to check it. See
  # scripts/generate_oscal_element_order.rb; drift is caught by
  # spec/lib/oscal_element_order_spec.rb.
  ELEMENT_ORDER_PATH = Rails.root.join("lib/oscal_element_order.json").freeze

  def self.element_order
    @element_order ||= JSON.parse(ELEMENT_ORDER_PATH.read).freeze
  end

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
  # OSCAL element names that collide with a real Ruby/Nokogiri::XML::Builder
  # method. Because elements are emitted with `send`, these would invoke that
  # method instead of creating an element. Derived from the builder's own method
  # table so it cannot drift, with the OSCAL names we know appear as elements.
  COLLIDING_ELEMENT_NAMES = (
    %w[select class] +
    (Nokogiri::XML::Builder.instance_methods +
     Nokogiri::XML::Builder.private_instance_methods).map(&:to_s)
  ).to_set.freeze

  ATTRIBUTE_KEYS = Set.new(%w[
    uuid id href rel type name value ns class
    role-id component-uuid control-id param-id statement-id
    state identifier-type system media-type
    how-many
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

    root_type = self.class.element_order.dig("roots", @root_key)
    root_entry = type_entry(root_type)

    builder = Nokogiri::XML::Builder.new(encoding: "UTF-8") do |xml|
      attrs = extract_attributes(root_data, root_entry).merge("xmlns" => OSCAL_NS)
      xml.send(safe_element_name(@root_key), attrs) do
        hash_children_to_xml(xml, root_data, root_type)
      end
    end

    builder.to_xml
  end

  private

  def type_entry(name)
    name && self.class.element_order.dig("types", name)
  end

  # Extract attribute-eligible key/value pairs from a hash.
  #
  # Which keys are attributes is a PER-TYPE fact: `name` is an attribute of
  # <prop> but a child element of <party>, and `start`/`end` are attributes only
  # on <port-range>. When the schema type is known its attribute list decides;
  # ATTRIBUTE_KEYS remains the fallback for hashes the schema does not describe.
  def extract_attributes(hash, entry = nil)
    allowed = entry && entry["attributes"]

    hash.each_with_object({}) do |(key, value), attrs|
      next unless scalar?(value)
      next unless allowed ? allowed.include?(key) : ATTRIBUTE_KEYS.include?(key)

      attrs[key] = value.to_s
    end
  end

  # Render only the non-attribute children of a hash, in XSD sequence order.
  #
  # `type_name` is the parent's XSD type. When it is unknown — an OSCAL
  # extension, or a key the schema does not define — ordering is skipped for
  # that hash and insertion order is kept. Unknown keys are NEVER dropped:
  # emitting them out of order still round-trips the data, whereas discarding
  # them would lose it silently.
  def hash_children_to_xml(xml, hash, type_name = nil)
    entry = type_entry(type_name)

    ordered_children(hash, entry).each do |key, value|
      emit_child(xml, key, value, entry)
    end
  end

  # Sort by the child's position in the parent's `xs:sequence`. Keys the schema
  # does not know sort last, and the original index breaks ties so the result is
  # stable — Ruby's sort_by is not.
  def ordered_children(hash, entry)
    attrs = extract_attributes(hash, entry)
    children = hash.reject { |key, _value| attrs.key?(key) }
    order = entry && entry["order"]
    return children.to_a if order.blank?

    children.each_with_index
            .sort_by { |(key, value), index| [ order.index(element_name_for(key, value, entry)) || order.size, index ] }
            .map(&:first)
  end

  # The element name this key will actually be emitted as.
  #
  # Most OSCAL JSON arrays repeat a singular element in XML (`controls` =>
  # <control>...), but some are GROUPED behind a real wrapper element the schema
  # declares (`revisions` => <revisions><revision/></revisions>).
  #
  # NAMING and GROUPING are separate questions. If the schema declares the key
  # itself, that is the element's name — whether it then wraps its items
  # (`revisions`) or simply repeats (`satisfied`, `include-controls`) is decided
  # by `wrapper?` at emit time.
  def element_name_for(key, value, entry)
    return key unless value.is_a?(Array)

    order = entry && entry["order"]
    return key if order&.include?(key)

    mapped = PLURAL_TO_SINGULAR[key]
    return mapped if mapped && (order.nil? || order.include?(mapped))

    # Fall back to the schema rather than to the hand-written plural map: if a
    # naive singular of this key is a child the parent actually declares, that
    # is the element name. This is why `email-addresses` and
    # `control-implementations` convert correctly without being listed.
    derived = order && naive_singulars(key).find { |candidate| order.include?(candidate) }
    return derived if derived

    # Last, OSCAL's own JSON-to-XML group names, for the cases where the two
    # differ outright: `remediations` is <response>, `related-risks` is
    # <associated-risk>. Only accepted when the parent really declares it.
    aliased = order && Array(self.class.element_order.dig("json_aliases", key))
                       .find { |candidate| order.include?(candidate) }

    aliased || mapped || key
  end

  def naive_singulars(key)
    [ key.sub(/ies\z/, "y"), key.sub(/es\z/, ""), key.sub(/s\z/, "") ].uniq
  end

  def wrapper?(parent_entry, key)
    return false unless parent_entry

    type_entry(parent_entry.dig("children", key))&.key?("wraps") || false
  end

  def emit_child(xml, key, value, parent_entry)
    element = element_name_for(key, value, parent_entry)
    entry = type_entry(parent_entry&.dig("children", element))

    if value.is_a?(Array) && element == key && wrapper?(parent_entry, key)
      emit_grouped(xml, element, value, entry)
    elsif value.is_a?(Array)
      value.each { |item| emit_element(xml, element, item, entry) }
    else
      emit_element(xml, element, value, entry)
    end
  end

  # A GROUPED array: one wrapper element containing the repeated child the
  # wrapper's own type declares.
  def emit_grouped(xml, element, items, entry)
    item_name = entry&.dig("wraps") || singularize_key(element, items.first)
    item_entry = type_entry(entry&.dig("children", item_name))

    xml.send(safe_element_name(element)) do
      items.each { |item| emit_element(xml, item_name, item, item_entry) }
    end
  end

  def emit_element(xml, name, value, entry)
    return if value.nil?

    if entry&.dig("markup")
      emit_markup(xml, name, value, entry)
    elsif value.is_a?(Hash)
      emit_hash_element(xml, name, value, entry)
    elsif value.is_a?(Array)
      value.each { |item| emit_element(xml, name, item, entry) }
    elsif scalar?(value)
      emit_scalar(xml, name, value, entry)
    end
  end

  # OSCAL prose. In JSON the prose of an element that also carries attributes
  # sits under the conventional key `prose`; elsewhere the value is the string
  # itself.
  #
  # markup-line (<title>) takes the text directly and REJECTS a <p> child;
  # markup-multiline (<description>, <remarks>) requires one. Emitting the
  # wrong one is invalid either way, so the schema decides.
  def emit_markup(xml, name, value, entry)
    attrs = value.is_a?(Hash) ? extract_attributes(value, entry) : {}
    text  = value.is_a?(Hash) ? value["prose"] : value

    return xml.send(safe_element_name(name), text.to_s, attrs) if entry&.dig("markup") == "line"

    xml.send(safe_element_name(name), attrs) do
      text.to_s.split("\n").reject(&:blank?).each { |para| xml.p para.strip }
    end
  end

  def emit_scalar(xml, name, value, entry)
    # Fallback for prose the schema does not type for us: without an entry we
    # cannot know an element is markup, so keep the original key heuristic.
    if entry.nil? && value.is_a?(String) && (name == "description" || name == "remarks" || contains_markup?(value))
      return emit_markup(xml, name, value, nil)
    end

    xml.send(safe_element_name(name), value.to_s)
  end

  def emit_hash_element(xml, name, hash, entry)
    attrs = extract_attributes(hash, entry)
    remaining = hash.reject { |key, _| attrs.key?(key) }

    # `xs:simpleContent`: attributes PLUS a text value. The one non-attribute
    # key supplies the text, e.g. {"scheme": ..., "identifier": "x"} =>
    # <document-id scheme="...">x</document-id>.
    if entry&.dig("text")
      text = remaining.values.find { |v| scalar?(v) }
      return xml.send(safe_element_name(name), text.to_s, attrs) if text
    end

    if remaining.empty?
      xml.send(safe_element_name(name), attrs)
    else
      xml.send(safe_element_name(name), attrs) do
        ordered_children(hash, entry).each { |key, value| emit_child(xml, key, value, entry) }
      end
    end
  end

  # OSCAL JSON arrays use plural keys, but XML repeats the singular element.
  #
  # NOT the authority since #827 — `element_name_for` resolves names against the
  # parent's schema first, and only consults this map for hashes the schema does
  # not describe. Entries that disagree with the schema are simply not used
  # (`remediations` is listed here as `remediation` but converts to <response>),
  # so do not add to it to fix a conversion: regenerate the ordering table.
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

  # Ensure element names are valid for Nokogiri builder.
  #
  # Nokogiri's builder creates elements via method_missing, but we dispatch with
  # `send`, which finds any REAL method of that name first — including private
  # Kernel ones. OSCAL catalogs nest <select> inside <param>, so `send(:select,
  # attrs)` called Kernel#select (IO.select) and raised
  # "TypeError: wrong argument type Hash (expected Array)", making XML export of
  # every control catalog fail. `class` collides the same way.
  #
  # A trailing underscore is Nokogiri's documented escape hatch — it strips one
  # when creating the element, so "select_" emits <select>.
  def safe_element_name(name)
    return "#{name}_" if COLLIDING_ELEMENT_NAMES.include?(name.to_s)

    name
  end

  def scalar?(value)
    value.is_a?(String) || value.is_a?(Numeric) || value.is_a?(TrueClass) || value.is_a?(FalseClass)
  end

  def contains_markup?(str)
    str.include?("\n") && str.length > 100
  end
end
