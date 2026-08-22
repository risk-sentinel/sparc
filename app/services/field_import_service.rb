# frozen_string_literal: true

require "yaml"
require "json"

# #716 (P1, follow-on to #697/#715) — bulk file import of editable control
# FIELDS for the downstream document types (SSP / SAR / SAP / CDEF), following
# the OdpImportService preview -> confirm pattern the P0 ODP import proved.
#
# Input is a structured file (JSON or YAML) of:
#   { "controls": { "<control_id>": { "<field_name>": "<value>", ... }, ... } }
# (a bare { "<control_id>": {...} } map is also accepted). It normalizes to a
# non-destructive preview diff and then applies atomically via the control-field
# models — one uniform model-level write path for all four types (#716 design
# decision), mirroring how each controller's update_fields already writes.
#
# `preview` classifies each field: change / unchanged / unknown (control id) /
# non_editable / invalid (allowed_values violation). `apply` writes only the
# editable, allowed change/unchanged rows, atomically, with a partial-success
# summary; the controller audits.
#
# NIST 800-53: SI-10 (input validation on the uploaded file), AC-3 (boundary
# authz — enforced by the controller), CM-3/CM-4 (config change control),
# AU-12 (audit — emitted by the controller).
class FieldImportService
  class ImportError < StandardError; end

  SUPPORTED_FORMATS = %w[json yaml yml].freeze

  # Per-document-type wiring. Associations follow the naming convention; the
  # field_class owns EDITABLE_FIELDS + allowed_values.
  CONFIG = {
    "SspDocument"  => { controls: :ssp_controls,  fields: :ssp_control_fields,  field_class: SspControlField },
    "SarDocument"  => { controls: :sar_controls,  fields: :sar_control_fields,  field_class: SarControlField },
    "SapDocument"  => { controls: :sap_controls,  fields: :sap_control_fields,  field_class: SapControlField },
    "CdefDocument" => { controls: :cdef_controls, fields: :cdef_control_fields, field_class: CdefControlField }
  }.freeze

  # One classified line of a preview diff.
  # `control_id` is the key the CALLER used, echoed back verbatim.
  # `resolved_uuid` is the control that key actually resolved to — #1028: a key
  # that matched a different row than the caller expected was the whole defect,
  # so the response now says which row was written.
  Row = Struct.new(
    :control_id, :resolved_uuid, :field_name, :current_value, :new_value, :status, :message,
    keyword_init: true
  ) do
    def to_h
      super.compact
    end
  end

  # Parse raw file content into the canonical payload. Stateless.
  # @return [Hash] { controls: [ { control_id:, fields: {name=>value} } ] }
  def self.parse(content:, format:)
    fmt = format.to_s.strip.downcase.delete_prefix(".")
    raise ImportError, "Empty file" if content.to_s.strip.empty?

    data =
      case fmt
      when "json"        then parse_json(content)
      when "yaml", "yml" then parse_yaml(content)
      else
        raise ImportError, "Unsupported format '#{fmt}'. Use one of: #{SUPPORTED_FORMATS.join(', ')}"
      end
    coerce(data)
  end

  def initialize(document)
    @document = document
    @config = CONFIG.fetch(document.class.name) do
      raise ImportError, "Field import is not supported for #{document.class.name}"
    end
  end

  # Non-destructive diff — no writes.
  def preview(payload)
    field_class = @config[:field_class]
    rows = []

    Array(payload[:controls]).each do |entry|
      cid = entry[:control_id]
      control, failure = resolve_control(cid)

      Hash(entry[:fields]).each do |fname, value|
        fname = fname.to_s
        new_value = value.to_s

        if control.nil?
          rows << Row.new(control_id: cid, field_name: fname, new_value: new_value,
                          status: failure[:status], message: failure[:message])
          next
        end
        unless field_class::EDITABLE_FIELDS.include?(fname)
          rows << Row.new(control_id: cid, resolved_uuid: control.uuid, field_name: fname,
                          new_value: new_value,
                          status: "non_editable", message: "Field is not editable")
          next
        end
        allowed = field_class.allowed_values(fname)
        if allowed && !allowed.include?(new_value)
          rows << Row.new(control_id: cid, resolved_uuid: control.uuid, field_name: fname,
                          new_value: new_value,
                          status: "invalid", message: "Not an allowed value: #{allowed.join(', ')}")
          next
        end

        current = current_value(control, fname)
        rows << Row.new(control_id: cid, resolved_uuid: control.uuid, field_name: fname,
                        current_value: current, new_value: new_value,
                        status: current == new_value ? "unchanged" : "change")
      end
    end

    { rows: rows, stats: tally(rows) }
  end

  # Atomic apply of only the editable, allowed change/unchanged rows. Unknown /
  # non_editable / invalid rows are reported but never written. Partial-success.
  def apply(payload)
    rows = preview(payload)[:rows]
    applied = 0

    ActiveRecord::Base.transaction do
      rows.each do |row|
        next unless %w[change unchanged].include?(row.status)

        # #1028 — write to the row the PREVIEW resolved, addressed by uuid.
        # Re-running key resolution here would let preview and confirm disagree
        # whenever a key is ambiguous, which is precisely the defect: preview
        # described one control and confirm wrote another.
        control = control_by_uuid.fetch(row.resolved_uuid)
        field = control.public_send(@config[:fields]).find_or_initialize_by(field_name: row.field_name)
        field.field_value = row.new_value
        field.save!
        applied += 1 if row.status == "change"
      end
    end

    @document.regenerate_oscal_uuid! if @document.respond_to?(:regenerate_oscal_uuid!)
    { applied: applied, stats: tally(rows), rows: rows.map(&:to_h) }
  end

  private

  # Every control on the document, fields preloaded (the component lookup below
  # reads one, and resolution touches every control).
  def controls
    @controls ||= @document.public_send(@config[:controls])
                           .includes(@config[:fields])
                           .order(:row_order)
                           .to_a
  end

  def control_by_uuid
    @control_by_uuid ||= controls.index_by { |c| c.uuid.to_s }
  end

  # #1028 — resolve the key the caller wrote to exactly one control, or refuse.
  #
  # `control_id` is not an identifier on every document type. On a CDEF it is
  # the NIST reference a Converter RESOLVED at ingest (#912), so it is non-unique
  # by design — two components can implement the same control — and NULL where
  # translation resolved nothing. Keying on it and taking "first wins" over an
  # unordered association wrote to a control the caller never named and could
  # not see: measured on `aws-elasticbeanstalk-oscal-1-2-1`, `ca-7` resolved to
  # the row at row_order 3 while every read surface presents row_order 0.
  #
  # Accepted keys, in preference order:
  #
  #   1. the control's `uuid` — exact, stable, unique on all four types;
  #   2. `"<component>::<source_control_id>"` — the identity a CDEF row actually
  #      has, and the identifier an AWS/CIS/DISA caller holds;
  #   3. `source_control_id` alone, where it names exactly one control;
  #   4. `control_id`, canonicalised (#911), where it names exactly one control.
  #
  # A key matching more than one control is REFUSED and named, never resolved
  # silently. "I do not know which one you mean" must not be answered with a
  # successful write.
  #
  # @return [Array(control, failure_hash)] one of the two is always nil.
  def resolve_control(raw_key)
    key = raw_key.to_s.strip
    return [ nil, { status: "unknown", message: "No control id given" } ] if key.empty?

    if (exact = control_by_uuid[key])
      return [ exact, nil ]
    end

    candidates = candidates_for(key)
    return [ candidates.first, nil ] if candidates.size == 1
    return [ nil, { status: "unknown", message: "Unknown control id for this document" } ] if candidates.empty?

    [ nil, { status: "ambiguous", message: ambiguity_message(key, candidates) } ]
  end

  def candidates_for(key)
    if key.include?("::")
      component, source = key.split("::", 2).map(&:strip)
      return controls.select do |c|
        source_identifier(c).to_s.casecmp?(source) && component_name(c).to_s.casecmp?(component)
      end
    end

    by_source = controls.select { |c| source_identifier(c).to_s.casecmp?(key) }
    return by_source if by_source.any?

    canonical = ControlId.canonical(key)
    controls.select { |c| c.control_id.present? && ControlId.canonical(c.control_id) == canonical }
  end

  # Name every candidate the way the caller can address it, so the refusal is
  # actionable rather than merely correct.
  def ambiguity_message(key, candidates)
    listed = candidates.first(10).map do |c|
      identity = [ component_name(c), source_identifier(c) ].compact_blank.join("::")
      identity.present? ? "#{c.uuid} (#{identity})" : c.uuid.to_s
    end
    more = candidates.size > listed.size ? ", and #{candidates.size - listed.size} more" : ""

    "'#{key}' matches #{candidates.size} controls in this document. Address one " \
      "explicitly by uuid, or by \"component::source_control_id\": " \
      "#{listed.join(', ')}#{more}"
  end

  # CDEF carries the native identifier and its vocabulary in their own columns
  # (#912). The other three types key directly on NIST controls and have neither.
  def source_identifier(control)
    control.source_control_id if control.respond_to?(:source_control_id)
  end

  # The component a CDEF control belongs to is stored as a control FIELD, not a
  # column — which is why two rows can share a control_id and a source id and
  # still be different rows.
  def component_name(control)
    return nil unless control.respond_to?(:cdef_control_fields)

    control.cdef_control_fields.find { |f| f.field_name == "component" }&.field_value
  end

  def current_value(control, field_name)
    control.public_send(@config[:fields]).find_by(field_name: field_name)&.field_value.to_s
  end

  def tally(rows)
    {
      total:        rows.size,
      changes:      rows.count { |r| r.status == "change" },
      unchanged:    rows.count { |r| r.status == "unchanged" },
      unknown:      rows.count { |r| r.status == "unknown" },
      ambiguous:    rows.count { |r| r.status == "ambiguous" },
      non_editable: rows.count { |r| r.status == "non_editable" },
      invalid:      rows.count { |r| r.status == "invalid" }
    }
  end

  def self.parse_json(content)
    JSON.parse(content)
  rescue JSON::ParserError => e
    raise ImportError, "Invalid JSON: #{e.message.truncate(120)}"
  end
  private_class_method :parse_json

  def self.parse_yaml(content)
    YAML.safe_load(content, permitted_classes: [], aliases: false)
  rescue Psych::SyntaxError => e
    raise ImportError, "Invalid YAML: #{e.message.truncate(120)}"
  end
  private_class_method :parse_yaml

  # Normalize to { controls: [ { control_id:, fields: {} } ] }. Accepts the
  # canonical { "controls": { id => {field=>val} } } or a bare { id => {..} } map.
  def self.coerce(data)
    raise ImportError, "Unrecognized structure — expected an object of controls" unless data.is_a?(Hash)

    controls_map = data["controls"] || data[:controls] || data
    unless controls_map.is_a?(Hash)
      raise ImportError, "Expected 'controls' to be an object of { control_id => { field => value } }"
    end

    controls = controls_map.filter_map do |cid, fields|
      next if cid.to_s.strip.empty? || !fields.is_a?(Hash)

      { control_id: cid.to_s, fields: fields }
    end
    raise ImportError, "No control field updates found" if controls.empty?

    { controls: controls }
  end
  private_class_method :coerce
end
