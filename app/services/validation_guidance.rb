# frozen_string_literal: true

# For each error of a version that failed validation: where it is, what is
# wrong in plain words, and what the provider needs to send (#1390 part G;
# owner, 2026-11-23).
#
# For a FedRAMP document "what is needed" comes from FedRAMP's own schema:
# the stored bytes are checked again against the vendored schema, so each
# error carries the schema node that failed (its allowed values, format or
# type), and the field's title and description come from the schema too
# (FieldGuide). Errors of other formats (OSCAL, HDF, XCCDF, unreadable
# documents) keep the validator's message; "what is needed" is left blank
# rather than guessed.
#
#   ValidationGuidance.new(document).items.each do |item|
#     item.label   # => "Vulnerabilities › ECW-VULN-0013 › Vulnerability description"
#     item.wrong   # => "Vulnerability description is blank."
#     item.needed  # => "A description of ... FedRAMP's schema requires it."
#   end
#
# NIST SP 800-53: SI-10 (information input validation: the error is
# explained, never acted on), CA-2.
class ValidationGuidance
  Item = Data.define(:check, :pointer, :location, :label, :wrong, :needed, :message)
  MAX_ITEMS = 200
  EXAMPLES = { "date-time" => "2026-11-23T14:00:00Z", "date" => "2026-11-23", "uri" => "https://example.com/path",
               "email" => "name@example.com" }.freeze
  TYPE_NAMES = { "string" => "text", "array" => "a list", "object" => "an object", "integer" => "a whole number",
                 "number" => "a number", "boolean" => "true or false", "null" => "empty" }.freeze

  def initialize(document)
    @document = document
  end

  def items
    @items ||= build
  end

  private

  def build
    errors = @document.validation_errors.select { |e| e.is_a?(Hash) }.first(MAX_ITEMS)
    return [] if errors.empty?

    data = parsed
    details = schema_details(data)
    errors.map do |error|
      pointer = error["pointer"].to_s
      location = data ? ExchangeDelta::JsonDiff.keyed_pointer(data, pointer) : pointer
      detail = details.find { |d| d["data_pointer"] == pointer && d["error"] == error["message"] } ||
               details.find { |d| d["data_pointer"] == pointer }
      wrong, needed = explain(error, detail, data, pointer, location)
      Item.new(check: error["check"].to_s, pointer: pointer, location: location,
               label: ReceivedDocumentViewer.pointer_label(location), wrong: wrong, needed: needed,
               message: error["message"].to_s)
    end
  end

  def fedramp? = @document.format == "fedramp" && @document.document_type.present?

  def parsed
    raw = @document.bytes
    return nil if raw.nil? || ExchangeDelta.xml?(raw)

    ExchangeDelta.parse_json(raw)
  rescue StandardError
    nil
  end

  # json_schemer's own error records for the stored bytes (data pointer, the
  # failing schema node and its type).
  def schema_details(data)
    return [] unless fedramp? && data.is_a?(Hash)

    FedrampPackageSchemas.schemer(@document.document_type).validate(data).first(MAX_ITEMS).to_a
  rescue StandardError
    []
  end

  def explain(error, detail, data, pointer, _location)
    field = last_field(pointer)
    name = field ? ReceivedDocumentViewer::Layouts.label(field) : "The document"
    return completeness(name, field) if error["check"] == "completeness"
    return [ error["message"].to_s, nil ] unless detail

    value = dig(data, pointer)
    node = detail["schema"].is_a?(Hash) ? detail["schema"] : {}
    case detail["type"]
    when "required"
      missing = Array(detail.dig("details", "missing_keys"))
      [ "#{name} is missing #{missing.map { |k| ReceivedDocumentViewer::Layouts.label(k) }.to_sentence}.",
        missing.map { |k| guide_sentence(k) || "#{ReceivedDocumentViewer::Layouts.label(k)}." }.join(" ") + " FedRAMP's schema requires #{missing.size == 1 ? 'it' : 'them'}." ]
    when "enum"
      [ "#{name} is #{quoted(value)}, which is not an allowed value.",
        [ "One of: #{Array(node['enum']).join(', ')}.", guide_description(field) ].compact.join(" ") ]
    when "format"
      fmt = node["format"].to_s
      [ "#{name} is #{quoted(value)}, which is not a valid #{fmt}.",
        "A #{fmt} value#{EXAMPLES[fmt] ? ", for example #{EXAMPLES[fmt]}" : ''}." ]
    when *TYPE_NAMES.keys
      [ "#{name} is #{TYPE_NAMES.fetch(json_type(value), json_type(value))}, not #{TYPE_NAMES.fetch(detail['type'])}.",
        [ "#{TYPE_NAMES.fetch(detail['type']).capitalize}.", guide_description(field) ].compact.join(" ") ]
    when "pattern"
      [ "#{name} is #{quoted(value)}, which is not in the expected form.", "A value matching #{node['pattern']}." ]
    else
      [ error["message"].to_s, guide_sentence(field) ]
    end
  end

  def completeness(name, field)
    [ "#{name} is blank.", "#{guide_sentence(field) || "#{name}."} FedRAMP's schema requires it." ]
  end

  def guide_sentence(field)
    entry = field && FieldGuide.lookup(field)
    return nil unless entry

    [ entry["title"], entry["description"] ].compact.uniq.join(": ").then { |s| s.end_with?(".") ? s : "#{s}." }
  end

  def guide_description(field)
    entry = field && FieldGuide.lookup(field)
    entry && entry["description"] ? entry["description"].then { |s| s.end_with?(".") ? s : "#{s}." } : nil
  end

  # The field an error is about: the last segment of the validator's
  # positional pointer that is not a list position.
  def last_field(pointer)
    ExchangeDelta::JsonDiff.segments(pointer).reverse.find { |s| !s.match?(/\A\d+\z/) }
  end

  def dig(data, pointer)
    ExchangeDelta::JsonDiff.segments(pointer).reduce(data) do |node, seg|
      case node
      when Hash then node[seg]
      when Array then seg.match?(/\A\d+\z/) ? node[seg.to_i] : nil
      else return nil
      end
    end
  end

  def quoted(value) = value.is_a?(String) ? "“#{value.truncate(80)}”" : value.inspect.truncate(80)

  def json_type(value)
    case value
    when String then "string"
    when Array then "array"
    when Hash then "object"
    when Integer then "integer"
    when Numeric then "number"
    when true, false then "boolean"
    else "null"
    end
  end

  # The title, description, allowed values and format FedRAMP's schemas give
  # each field name, read from the vendored schemas once.
  module FieldGuide
    module_function

    def lookup(field) = index[field.to_s]

    def index
      @index ||= build.freeze
    end

    def reset! = (@index = nil)

    def build
      out = {}
      FedrampPackageSchemas.all.each_value do |schema|
        walk(schema.document, schema.document, out)
      end
      out
    end

    def walk(node, doc, out, depth = 0)
      return if depth > 40

      case node
      when Hash
        node["properties"].each { |name, sub| record(out, name, deref(sub, doc)) } if node["properties"].is_a?(Hash)
        node.each_value { |v| walk(v, doc, out, depth + 1) }
      when Array then node.each { |v| walk(v, doc, out, depth + 1) }
      end
    end

    def record(out, name, sub)
      return unless sub.is_a?(Hash)

      entry = sub.slice("title", "description", "enum", "format").compact
      return if entry.empty?

      out[name] = (out[name] || {}).reverse_merge(entry)
    end

    # A $ref within the same schema or to another vendored FedRAMP schema.
    def deref(sub, doc, hops = 0)
      return sub unless sub.is_a?(Hash) && sub["$ref"].is_a?(String) && hops < 5

      uri, fragment = sub["$ref"].split("#", 2)
      target = uri.blank? ? doc : FedrampPackageSchemas.ref_resolver.call(URI(uri))
      found = ExchangeDelta::JsonDiff.segments(fragment.to_s).reduce(target) { |n, seg| n.is_a?(Hash) ? n[seg] : nil }
      found.is_a?(Hash) ? deref(sub.except("$ref").reverse_merge(found), target, hops + 1) : sub
    rescue StandardError
      sub
    end
  end
end
