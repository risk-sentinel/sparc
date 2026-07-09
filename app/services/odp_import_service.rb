# frozen_string_literal: true

# Issue #697 (P0) — bulk file import of Organization-Defined Parameters
# (OSCAL `set-parameter` / ODP values) for a baseline/profile, following the
# CDEF `bulk_apply_converter` preview → confirm pattern.
#
# ODP values are the authoritative Catalog/Baseline/Profile layer: a catalog
# *defines* parameters, a profile (baseline) *sets* them. SPARC stores the set
# values on the profile (profile_control_fields), so the import operates on a
# ProfileDocument via BaselineParameterService — which already abstracts over
# both catalog-sourced and resolved-baseline profiles. Downstream doc types
# (CDEF/SSP/SAP/SAR) inherit these values from the upstream profile rather than
# importing their own.
#
# Parsing is format-tolerant (JSON / YAML / XML) and normalizes to the canonical
# update payload consumed by BaselineParameterService#update_parameters:
#   { parameters: [{ param_id:, value: }], selections: [{ select_id:, selected: [] }] }
#
# `preview` is a non-destructive dry-run diff (no writes); `confirm` (via #apply)
# delegates to the existing write path with partial-success reporting.
#
# NIST 800-53:
#   SI-10 (input validation on the uploaded file)
#   CM-3 / CM-4 (config change control on parameter updates)
#   AC-3 (boundary-scoped authorization — enforced by the controller)
#   AU-12 (audit on confirm — emitted by the controller)
class OdpImportService
  class ImportError < StandardError; end

  SUPPORTED_FORMATS = %w[json yaml yml xml].freeze

  # One classified line of a preview diff.
  Row = Struct.new(
    :param_id, :control_id, :kind, :current_value, :new_value, :status, :message,
    keyword_init: true
  ) do
    def to_h
      super.compact
    end
  end

  # Parse raw file content into the canonical update payload. Stateless — a
  # profile is not needed to normalize the file structure.
  #
  # @param content [String] raw file bytes
  # @param format  [String] "json" | "yaml" | "yml" | "xml"
  # @return [Hash] { parameters: [{param_id:, value:}], selections: [{select_id:, selected:[]}] }
  def self.parse(content:, format:)
    fmt = format.to_s.strip.downcase.delete_prefix(".")
    raise ImportError, "Empty file" if content.to_s.strip.empty?

    case fmt
    when "json"        then coerce(parse_json(content))
    when "yaml", "yml" then coerce(parse_yaml(content))
    when "xml"         then parse_xml(content)
    else
      raise ImportError, "Unsupported format '#{fmt}'. Use one of: #{SUPPORTED_FORMATS.join(', ')}"
    end
  end

  def initialize(profile)
    @profile = profile
    @service = BaselineParameterService.new(profile)
  end

  # Non-destructive diff: classify every parsed entry against the baseline's
  # current parameter schema. No writes.
  #
  # @param payload [Hash] canonical payload from .parse
  # @return [Hash] { rows: [Row], stats: {...} }
  def preview(payload)
    schema = @service.extract_schema
    params_by_id = schema[:parameters].index_by { |p| p[:param_id] }
    selects_by_id = schema[:selections].index_by { |s| s[:select_id] }

    rows = []

    Array(payload[:parameters]).each do |entry|
      pid = entry[:param_id]
      known = params_by_id[pid]
      if known.nil?
        rows << Row.new(param_id: pid, kind: "parameter", new_value: entry[:value].to_s,
                        status: "unknown", message: "Unknown parameter ID for this baseline")
        next
      end
      current = known[:current_value].to_s
      new_value = entry[:value].to_s
      rows << Row.new(param_id: pid, control_id: known[:control_id], kind: "parameter",
                      current_value: current, new_value: new_value,
                      status: current == new_value ? "unchanged" : "change")
    end

    Array(payload[:selections]).each do |entry|
      sid = entry[:select_id]
      selected = Array(entry[:selected]).map(&:to_s)
      new_value = selected.join(", ")
      known = selects_by_id[sid]
      if known.nil?
        rows << Row.new(param_id: sid, kind: "selection", new_value: new_value,
                        status: "unknown", message: "Unknown selection ID for this baseline")
        next
      end
      current = Array(known[:selected]).join(", ")
      invalid = selected - Array(known[:choices]).map(&:to_s)
      if invalid.any?
        rows << Row.new(param_id: sid, control_id: known[:control_id], kind: "selection",
                        current_value: current, new_value: new_value, status: "invalid",
                        message: "Not an allowed choice: #{invalid.join(', ')}")
      else
        rows << Row.new(param_id: sid, control_id: known[:control_id], kind: "selection",
                        current_value: current, new_value: new_value,
                        status: current == new_value ? "unchanged" : "change")
      end
    end

    { rows: rows, stats: tally(rows) }
  end

  # Apply the payload via the existing write path. BaselineParameterService
  # itself validates known ids and reports unknowns as validation_errors, giving
  # partial-success semantics. Invalid selection choices are dropped here so a
  # bad choice can't be persisted (preview surfaced them as `invalid`).
  #
  # @return [Hash] BaselineParameterService#update_parameters summary
  def apply(payload)
    @service.update_parameters(reject_invalid_selections(payload))
  end

  private

  def tally(rows)
    {
      total:     rows.size,
      changes:   rows.count { |r| r.status == "change" },
      unchanged: rows.count { |r| r.status == "unchanged" },
      unknown:   rows.count { |r| r.status == "unknown" },
      invalid:   rows.count { |r| r.status == "invalid" }
    }
  end

  # Strip selection entries whose choices aren't in the baseline schema so
  # confirm can't persist a value preview flagged as `invalid`.
  def reject_invalid_selections(payload)
    schema = @service.extract_schema
    selects_by_id = schema[:selections].index_by { |s| s[:select_id] }
    cleaned = Array(payload[:selections]).reject do |entry|
      known = selects_by_id[entry[:select_id]]
      next false if known.nil? # unknown ids are handled/validated downstream
      (Array(entry[:selected]).map(&:to_s) - Array(known[:choices]).map(&:to_s)).any?
    end
    { parameters: Array(payload[:parameters]), selections: cleaned }
  end

  # ---- format parsers (class-level) ----

  def self.parse_json(content)
    JSON.parse(content)
  rescue JSON::ParserError => e
    raise ImportError, "Invalid JSON: #{e.message.truncate(120)}"
  end
  private_class_method :parse_json

  def self.parse_yaml(content)
    require "yaml"
    YAML.safe_load(content, permitted_classes: [], aliases: false)
  rescue Psych::SyntaxError => e
    raise ImportError, "Invalid YAML: #{e.message.truncate(120)}"
  end
  private_class_method :parse_yaml

  # Parse the XML form — round-trips the `export` XML (schema_to_xml):
  #   <baseline-parameters>
  #     <parameters><parameter param-id="ac-1_prm_1"><value>ISSO</value></parameter></parameters>
  #     <selections><selection select-id="ac-2_prm_1"><selected>removes</selected></selection></selections>
  #   </baseline-parameters>
  # Strict parse; Nokogiri does not resolve external entities by default, so this
  # is not XXE-exposed (SI-10).
  def self.parse_xml(content)
    require "nokogiri"
    doc = Nokogiri::XML(content, &:strict)
    parameters = []
    selections = []

    doc.xpath("//parameter").each do |node|
      pid = (node["param-id"] || node["param_id"] || node.at_xpath("param-id")&.text).to_s.strip
      value = node.at_xpath("value")&.text || node["value"]
      parameters << { param_id: pid, value: value }
    end

    doc.xpath("//selection").each do |node|
      sid = (node["select-id"] || node["select_id"] || node.at_xpath("select-id")&.text).to_s.strip
      selected = node.xpath("selected").map { |s| s.text.strip }.reject(&:empty?)
      if selected.empty? && node["selected"].present?
        selected = node["selected"].split(/\s*[;,|]\s*/).reject(&:empty?)
      end
      selections << { select_id: sid, selected: selected }
    end

    if parameters.empty? && selections.empty?
      raise ImportError, "No <parameter> or <selection> elements found"
    end

    {
      parameters: parameters.reject { |p| p[:param_id].blank? },
      selections: selections.reject { |s| s[:select_id].blank? }
    }
  rescue Nokogiri::XML::SyntaxError => e
    raise ImportError, "Invalid XML: #{e.message.truncate(120)}"
  end
  private_class_method :parse_xml

  # Normalize a parsed JSON/YAML structure into the canonical payload. Accepts
  # the canonical {parameters:,selections:} object (round-trips the export
  # schema, which uses param_id/value), a flat { param_id => value } map, or a
  # bare array of row objects.
  def self.coerce(data)
    parameters = []
    selections = []

    if data.is_a?(Hash) && (data["parameters"] || data["selections"] || data[:parameters] || data[:selections])
      Array(data["parameters"] || data[:parameters]).each do |p|
        p = p.with_indifferent_access
        parameters << { param_id: (p[:param_id] || p[:id]).to_s, value: p[:value] }
      end
      Array(data["selections"] || data[:selections]).each do |s|
        s = s.with_indifferent_access
        selections << { select_id: (s[:select_id] || s[:id]).to_s, selected: Array(s[:selected]) }
      end
    elsif data.is_a?(Hash)
      data.each { |k, v| parameters << { param_id: k.to_s, value: v } }
    elsif data.is_a?(Array)
      data.each do |row|
        row = row.with_indifferent_access
        if row[:select_id] || row[:selected]
          selections << { select_id: (row[:select_id] || row[:id]).to_s, selected: Array(row[:selected]) }
        else
          parameters << { param_id: (row[:param_id] || row[:id]).to_s, value: row[:value] }
        end
      end
    else
      raise ImportError, "Unrecognized structure — expected an object or array of ODP values"
    end

    {
      parameters: parameters.reject { |p| p[:param_id].blank? },
      selections: selections.reject { |s| s[:select_id].blank? }
    }
  end
  private_class_method :coerce
end
