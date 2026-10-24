# frozen_string_literal: true

# The requirement text of each control and of each of its statement parts, with
# the baseline's organization-defined parameter values applied.
#
# One definition for every place an SSP author reads what a part requires: the
# SSP screen's per-part response rows and Required Statement block, and the
# `stated_requirement` SSP generation stores. They used to disagree:
#
# - generation stored only a statement's TOP-LEVEL prose, and NIST writes most
#   controls as a container with lettered `item` children and no prose of its
#   own, so 127 of the 287 MODERATE controls (ac-1 among them) were stored with
#   no requirement at all;
# - the per-part response rows showed a label ("a.", "1.", "(a)") and nothing
#   else, so an author could not see which requirement a box answered.
#
# Built from the catalog's stored part tree (`catalog_control_parts`, NIST's own
# ids: `ac-1_smt.a`, `ac-1_smt.a.1.a`), the same rows the resolved profile is
# built from, so a part id here is the `statement_id` of the SSP row it labels.
# Parameters resolve per part, aggregates included (OscalParameterResolver).
#
# NIST 800-53: PL-2 (the SSP states how each requirement is met), CM-6.
class ControlRequirementText
  # `required` — #1242: the part ids an SSP must answer, one response each: the
  # statement parts with no statement part below them, in catalog order. A
  # control whose catalog holds no parts has one, its `_smt`.
  Text = Struct.new(:full, :parts, :required, keyword_init: true) do
    def for_part(part_id) = parts[part_id.to_s]
  end

  STATEMENT_PARTS = %w[statement item].freeze

  def self.for_profile(profile)
    new(catalog: profile&.control_catalog, values: parameter_values(profile), alters: alters(profile))
  end

  # #1252 — canonical control id => the profile's stored alters for it.
  def self.alters(profile)
    return {} if profile.nil?

    profile.profile_controls.where.not(alters: []).pluck(:control_id, :alters)
           .to_h { |id, alters| [ ControlId.canonical(id), alters ] }
  end

  # param_id => the value the baseline sets. A blank value is not set.
  def self.parameter_values(profile)
    return {} if profile.nil?

    ProfileControlField.joins(:profile_control)
                       .where(profile_controls: { profile_document_id: profile.id })
                       .where("field_name LIKE 'parameter:%'")
                       .pluck(:field_name, :field_value)
                       .each_with_object({}) do |(name, value), values|
                         values[name.delete_prefix("parameter:")] = value if value.present?
                       end
  end

  def initialize(catalog:, values: {}, alters: {})
    @catalog = catalog
    @values = values || {}
    @alters = alters || {}
  end

  # @param control_ids [Array<String>] in any form (ac-1, AC-01, ac-2(1))
  # @return [Hash{String => Text}] keyed by canonical control id
  def for_controls(control_ids)
    wanted = Array(control_ids).map { |id| ControlId.canonical(id) }.uniq
    return {} if wanted.empty?

    catalog_controls = CatalogControl.guidance_index(wanted.flat_map { |id| ControlId.forms(id) }, catalog: @catalog).values
    parts = CatalogControlPart.where(catalog_control_id: catalog_controls.map(&:id), part_name: STATEMENT_PARTS)
                              .order(:catalog_control_id, :row_order)
                              .group_by(&:catalog_control_id)

    catalog_controls.each_with_object({}) do |control, result|
      key = ControlId.canonical(control.control_id)
      next unless wanted.include?(key)

      rows = parts[control.id] || []
      rows = altered_rows(control, rows, @alters[key]) if @alters[key].present?
      result[key] = text_for(control, rows)
    end
  end

  def for_control(control_id) = for_controls([ control_id ])[ControlId.canonical(control_id)]

  private

  def text_for(control, rows)
    resolver = OscalParameterResolver.new(control.effective_params_list.presence || control.params_list, @values)
    return flat_text(control, resolver) if rows.empty?

    depth = {}
    prose = {}
    lines = []
    parents = rows.filter_map(&:parent_part_id).to_set
    rows.each do |row|
      depth[row.part_id] = row.parent_part_id.present? ? depth.fetch(row.parent_part_id, -1) + 1 : -1
      text = row.prose.present? ? resolver.resolve_text(row.prose).strip : nil
      prose[row.part_id] = text if text.present?
      next if text.blank? && row.label.blank?

      lines << ("  " * [ depth[row.part_id], 0 ].max) + [ row.label, text ].compact_blank.join(" ")
    end
    Text.new(full: lines.join("\n"), parts: prose, required: rows.map(&:part_id).reject { parents.include?(_1) })
  end

  # #1252 — the statement rows as the profile's alters leave them: removed
  # items gone, added items in place. Rebuilt into the OSCAL tree, altered by
  # ProfileAlterations (the definition the resolved catalog uses), and read
  # back depth-first, which is the stored row order.
  Row = Struct.new(:part_id, :parent_part_id, :label, :prose, keyword_init: true)

  def altered_rows(control, rows, alters)
    nodes = rows.to_h do |row|
      node = { "id" => row.part_id, "name" => row.part_name }
      node["props"] = [ { "name" => "label", "value" => row.label } ] if row.label.present?
      node["prose"] = row.prose if row.prose.present?
      [ row.part_id, node ]
    end
    roots = []
    rows.each do |row|
      parent = row.parent_part_id.present? && nodes[row.parent_part_id]
      parent ? (parent["parts"] ||= []) << nodes[row.part_id] : roots << nodes[row.part_id]
    end

    tree = ProfileAlterations.new(alters).apply!({ "id" => control.control_id, "parts" => roots })
    flatten_parts(tree["parts"], nil)
  end

  def flatten_parts(parts, parent_id)
    Array(parts).flat_map do |part|
      next [] unless STATEMENT_PARTS.include?(part["name"].to_s)

      label = Array(part["props"]).find { |pr| pr["name"] == "label" }&.dig("value")
      [ Row.new(part_id: part["id"], parent_part_id: parent_id, label: label, prose: part["prose"]) ] +
        flatten_parts(part["parts"], part["id"])
    end
  end

  # A catalog imported before parts were stored has only the flattened
  # statement; it stands for the whole-control statement row.
  def flat_text(control, resolver)
    statement = (control.guidance_data || {})["statement"].to_s
    text = statement.present? ? resolver.resolve_text(statement).strip : ""
    Text.new(full: text, parts: text.present? ? { "#{control.control_id}_smt" => text } : {},
             required: [ "#{control.control_id}_smt" ])
  end
end
