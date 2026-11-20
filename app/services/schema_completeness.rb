# frozen_string_literal: true

# Is a document COMPLETE by its schema's own definitions (#1354)?
#
# JSON Schema validation answers "is it well formed?". FedRAMP's package
# schemas never set minLength, so an empty string passes every `required`
# check, and a package of blank fields validates. This walks the document
# beside its schema and reports:
#
#   errors   — a required field that is present but blank (see blank_for?:
#              whitespace-only text, an unwanted null, or an empty object its
#              schema gives fields to). A missing required field is the schema
#              check's finding, not repeated here.
#   warnings — (warn_optional: true) a field the schema defines but the
#              document leaves out or leaves blank, where an enclosing object
#              is present.
#
# It follows $ref (local `#/$defs/...`, `#/definitions/...`, `#anchor` ids,
# and other documents through the given resolver), allOf, if/then/else,
# oneOf/anyOf (the first branch the value satisfies), properties and items.
#
# NIST SP 800-53: SI-10 (information input validation).
class SchemaCompleteness
  Finding = Struct.new(:pointer, :message, keyword_init: true) do
    def to_h = { pointer: pointer, message: message }
  end

  Report = Struct.new(:errors, :warnings, :warnings_total, keyword_init: true)

  MAX_DEPTH = 64
  MAX_WARNINGS = 200

  # @param schema [Hash] the root schema document
  # @param resolver [#call, nil] uri -> schema Hash, for refs to other documents
  # @param warn_optional [Boolean] report absent or blank optional fields
  def initialize(schema, resolver: nil, warn_optional: false)
    @root = schema
    @resolver = resolver
    @warn_optional = warn_optional
  end

  def check(document)
    @errors = []
    @warnings = []
    @warnings_total = 0
    @schemers = {}
    walk(document, @root, @root, "", 0)
    Report.new(errors: @errors, warnings: @warnings, warnings_total: @warnings_total)
  end

  private

  def walk(node, schema, base, pointer, depth)
    return if depth > MAX_DEPTH || !schema.is_a?(Hash)

    schema, base = resolve(schema, base)
    return unless schema.is_a?(Hash)

    Array(schema["allOf"]).each { |sub| walk(node, sub, base, pointer, depth + 1) }
    if schema.key?("if")
      branch = satisfies?(node, schema["if"], base) ? schema["then"] : schema["else"]
      walk(node, branch, base, pointer, depth + 1) if branch
    end
    %w[oneOf anyOf].each do |key|
      next unless schema[key].is_a?(Array)

      match = schema[key].find { |sub| satisfies?(node, sub, base) }
      walk(node, match, base, pointer, depth + 1) if match
    end

    case node
    when Hash then walk_object(node, schema, base, pointer, depth)
    when Array then walk_array(node, schema, base, pointer, depth)
    else nil # a scalar has no fields of its own to check
    end
  end

  def walk_object(node, schema, base, pointer, depth)
    required = Array(schema["required"])
    properties = schema["properties"].is_a?(Hash) ? schema["properties"] : {}

    required.each do |key|
      next unless node.key?(key) && blank_for?(node[key], properties[key], base)

      @errors << Finding.new(pointer: "#{pointer}/#{escape(key)}", message: "required field is blank")
    end

    properties.each do |key, sub|
      child = "#{pointer}/#{escape(key)}"
      if node.key?(key)
        value = node[key]
        if blank_for?(value, sub, base)
          warn(child, "optional field is blank") unless required.include?(key)
        else
          walk(value, sub, base, child, depth + 1)
        end
      elsif !required.include?(key)
        warn(child, "optional field is not filled in")
      end
    end
  end

  # Blank by what the schema says the field is for:
  #   - a string of only whitespace is blank;
  #   - null is blank unless the schema allows null;
  #   - an empty object is blank only when its schema defines fields for it
  #     (OSCAL's `include-all: {}` is a complete answer: "all of them");
  #   - an empty array is never blank here: the schema's minItems decides, and
  #     some schemas define [] as an answer (FedRAMP's OCR: `incidents: []`
  #     attests to no incidents).
  def blank_for?(value, subschema, base)
    case value
    when nil then !allows_null?(subschema, base)
    when String then value.strip.empty?
    when Hash then value.empty? && defines_fields?(subschema, base)
    else false
    end
  end

  def allows_null?(subschema, base)
    sub, = resolve(subschema, base)
    return false unless sub.is_a?(Hash)

    Array(sub["type"]).include?("null") || Array(sub["enum"]).include?(nil) || sub.key?("const") && sub["const"].nil?
  end

  def defines_fields?(subschema, base)
    sub, = resolve(subschema, base)
    sub.is_a?(Hash) && (sub["properties"].is_a?(Hash) && sub["properties"].any? || Array(sub["required"]).any?)
  end

  def walk_array(node, schema, base, pointer, depth)
    items = schema["items"]
    return unless items.is_a?(Hash)

    node.each_with_index { |item, i| walk(item, items, base, "#{pointer}/#{i}", depth + 1) }
  end

  def warn(pointer, message)
    return unless @warn_optional

    @warnings_total += 1
    @warnings << Finding.new(pointer: pointer, message: message) if @warnings.size < MAX_WARNINGS
  end

  # Follows `$ref` until the schema is not a bare reference. Returns the
  # schema and the document it lives in, so a ref inside a referenced
  # document resolves against that document.
  def resolve(schema, base, hops = 0)
    while schema.is_a?(Hash) && schema["$ref"].is_a?(String) && hops < MAX_DEPTH
      ref = schema["$ref"]
      doc_part, fragment = ref.split("#", 2)
      target_base = doc_part.to_s.empty? ? base : external(doc_part)
      return [ nil, base ] unless target_base

      target = fragment_target(target_base, fragment.to_s)
      # Keep any sibling keywords next to the $ref (2020-12 allows them).
      siblings = schema.except("$ref")
      schema = siblings.empty? || !target.is_a?(Hash) ? target : target.merge(siblings)
      base = target_base
      hops += 1
    end
    [ schema, base ]
  end

  def external(uri)
    return nil unless @resolver

    @resolver.call(URI(uri))
  rescue StandardError
    nil
  end

  def fragment_target(doc, fragment)
    return doc if fragment.empty?
    return dig_pointer(doc, fragment) if fragment.start_with?("/")

    anchors(doc)[fragment]
  end

  def dig_pointer(doc, pointer)
    pointer.split("/").drop(1).reduce(doc) do |node, token|
      key = token.gsub("~1", "/").gsub("~0", "~")
      case node
      when Hash then node[key]
      when Array then node[key.to_i]
      else nil # the pointer runs past a scalar: nothing there
      end
    end
  end

  # OSCAL's JSON schemas name definitions by `$id: "#name"`; 2019+ schemas by
  # `$anchor`.
  def anchors(doc)
    @anchors ||= {}
    @anchors[doc.object_id] ||= begin
      found = {}
      collect = lambda do |node|
        case node
        when Hash
          id = node["$id"]
          found[id.delete_prefix("#")] = node if id.is_a?(String) && id.start_with?("#")
          found[node["$anchor"]] = node if node["$anchor"].is_a?(String)
          node.each_value { |v| collect.call(v) }
        when Array
          node.each { |v| collect.call(v) }
        else nil # a scalar holds no definitions
        end
      end
      collect.call(doc)
      found
    end
  end

  def satisfies?(node, subschema, base)
    sub, sub_base = resolve(subschema, base)
    return false unless sub.is_a?(Hash)

    key = [ sub.object_id, sub_base.object_id ]
    schemer = (@schemers[key] ||= JSONSchemer.schema(standalone(sub, sub_base), ref_resolver: @resolver || ->(_) { }))
    schemer.valid?(node)
  rescue StandardError
    false
  end

  # A subschema evaluated on its own still needs its document's definitions
  # for local refs.
  def standalone(sub, base)
    defs = base.slice("$defs", "definitions", "$schema")
    defs.merge(sub)
  end

  def escape(key) = key.to_s.gsub("~", "~0").gsub("/", "~1")
end
