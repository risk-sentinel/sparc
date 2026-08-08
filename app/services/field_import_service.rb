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
  Row = Struct.new(
    :control_id, :field_name, :current_value, :new_value, :status, :message,
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
    controls_by_id = index_controls
    rows = []

    Array(payload[:controls]).each do |entry|
      cid = entry[:control_id]
      control = find_control(controls_by_id, cid)

      Hash(entry[:fields]).each do |fname, value|
        fname = fname.to_s
        new_value = value.to_s

        if control.nil?
          rows << Row.new(control_id: cid, field_name: fname, new_value: new_value,
                          status: "unknown", message: "Unknown control id for this document")
          next
        end
        unless field_class::EDITABLE_FIELDS.include?(fname)
          rows << Row.new(control_id: cid, field_name: fname, new_value: new_value,
                          status: "non_editable", message: "Field is not editable")
          next
        end
        allowed = field_class.allowed_values(fname)
        if allowed && !allowed.include?(new_value)
          rows << Row.new(control_id: cid, field_name: fname, new_value: new_value,
                          status: "invalid", message: "Not an allowed value: #{allowed.join(', ')}")
          next
        end

        current = current_value(control, fname)
        rows << Row.new(control_id: cid, field_name: fname, current_value: current, new_value: new_value,
                        status: current == new_value ? "unchanged" : "change")
      end
    end

    { rows: rows, stats: tally(rows) }
  end

  # Atomic apply of only the editable, allowed change/unchanged rows. Unknown /
  # non_editable / invalid rows are reported but never written. Partial-success.
  def apply(payload)
    rows = preview(payload)[:rows]
    controls_by_id = index_controls
    applied = 0

    ActiveRecord::Base.transaction do
      rows.each do |row|
        next unless %w[change unchanged].include?(row.status)

        control = find_control(controls_by_id, row.control_id)
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

  # control_id => control. SAR permits multiple controls per control_id
  # (test-row rows); first wins, mirroring the existing update_fields write path.
  #
  # #911 — keyed on the CANONICAL identifier, and looked up the same way. This
  # matched literally before, so an import file keyed `AC-1` found nothing when
  # the document stored `ac-1` (or `AC-01`), and every row came back `unknown`
  # rather than reporting a mismatch. The author sees "nothing to import" and no
  # reason why, which is the silent-no-op failure this issue exists to end.
  def index_controls
    @document.public_send(@config[:controls]).each_with_object({}) do |control, acc|
      acc[ControlId.canonical(control.control_id)] ||= control
    end
  end

  # The import file carries whatever spelling its author used, so resolve it the
  # same way rather than trusting the two to agree.
  def find_control(controls_by_id, raw_control_id)
    controls_by_id[ControlId.canonical(raw_control_id)]
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
