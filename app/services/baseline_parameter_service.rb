# frozen_string_literal: true

require "builder"
require "yaml"

# Extracts, exports, and updates OSCAL parameters and enumerations
# from a ProfileDocument's associated catalog or resolved baseline.
#
# Parameters are org-defined values (e.g., "lock after N attempts")
# and selections are enumeration choices (e.g., "VPN, tunneled, direct").
#
# Usage:
#   svc = BaselineParameterService.new(profile_document)
#   schema = svc.extract_schema               # → Hash with parameters/selections
#   svc.update_parameters(payload)             # → { status:, parameters_updated:, ... }
#   svc.export(format: :json)                  # → JSON/YAML/XML string
#
# NIST 800-53 Controls:
#   CM-6 Configuration Settings (parameter customization)
#   AC-3 Access Enforcement (API access control)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class BaselineParameterService
  class ValidationError < StandardError; end

  attr_reader :profile

  def initialize(profile_document)
    @profile = profile_document
  end

  # Extracts the full parameter and enumeration schema from the profile's
  # associated catalog controls or resolved_catalog_json.
  #
  # @param family [String, nil] optional control family filter (e.g., "AC")
  # @return [Hash] schema with :baseline, :version, :parameters, :selections
  def extract_schema(family: nil)
    raw_params = extract_raw_parameters(family: family)
    current_values = load_current_values
    # #942 — built from the UNFILTERED set: a selection in the AC family can
    # reference a parameter the `family:` filter would have excluded, and
    # resolving it to raw markup because of a display filter would be worse than
    # not filtering at all.
    resolver = OscalParameterResolver.new(extract_raw_parameters, current_values)

    parameters = []
    selections = []

    raw_params.each do |param|
      control_id = param["_control_id"]
      control_title = param["_control_title"]

      if param["select"].present?
        selections << build_selection(param, control_id, control_title, current_values, resolver)
      else
        parameters << build_parameter(param, control_id, control_title, current_values)
      end
    end

    {
      baseline: profile.name,
      baseline_level: profile.baseline_level,
      version: "1.0.0",
      profile_id: profile.id,
      profile_slug: profile.slug,
      parameters: parameters,
      selections: selections
    }
  end

  # Accepts a completed parameter schema and updates ProfileControlField entries.
  #
  # @param payload [Hash] with :parameters [{param_id:, value:}] and :selections [{select_id:, selected:[]}]
  # @return [Hash] summary with :status, :parameters_updated, :selections_updated, :validation_errors
  def update_parameters(payload)
    validation_errors = []
    params_updated = 0
    selections_updated = 0

    known_param_ids = extract_raw_parameters.map { |p| p["id"] }.to_set

    # Update parameters
    (payload[:parameters] || payload["parameters"] || []).each do |param_entry|
      param_id = param_entry[:param_id] || param_entry["param_id"]
      value = param_entry[:value] || param_entry["value"]

      unless known_param_ids.include?(param_id)
        validation_errors << { param_id: param_id, error: "Unknown parameter ID" }
        next
      end

      if upsert_parameter_field(param_id, value.to_s)
        params_updated += 1
      else
        # #1007 — nothing was written, so nothing is counted. Not reachable
        # today: `known_param_ids` and `find_control_id_for_param` read the same
        # extraction, and both extractors always set `_control_id`, so a param
        # that passes the guard above resolves here. It is kept because the
        # counter must never be able to run ahead of the writes again — that is
        # what made the old code report success for an update it had skipped —
        # and a future extractor that omits `_control_id` would otherwise
        # reintroduce it silently.
        validation_errors << {
          param_id: param_id,
          error: "Parameter is not attached to any control in this profile; nothing was written"
        }
      end
    end

    # Update selections
    (payload[:selections] || payload["selections"] || []).each do |sel_entry|
      select_id = sel_entry[:select_id] || sel_entry["select_id"]
      selected = sel_entry[:selected] || sel_entry["selected"] || []

      # #994 — an entry naming nothing cannot report which id was not found, so
      # it says what it is missing instead of reporting `select_id: null` under
      # "Unknown selection ID", which described the wrong problem. Callers reach
      # this through BaselineParameterPayload, which resolves the `selection_id`
      # alias; this is the guard for every other caller.
      if select_id.blank?
        validation_errors << { select_id: nil, error: "Selection entry is missing select_id" }
        next
      end

      unless known_param_ids.include?(select_id)
        validation_errors << { select_id: select_id, error: "Unknown selection ID" }
        next
      end

      # #994 — a non-array `selected` used to be coerced with `to_s` and
      # PERSISTED, reporting `selections_updated: 1` for a value the catalog
      # never offered as a choice. Refused rather than repaired: there is no
      # honest way to tell whether "a, b" was one choice or two.
      unless selected.is_a?(Array)
        validation_errors << {
          select_id: select_id,
          error: "selected must be an array of choice strings, even for a single choice"
        }
        next
      end

      # #942 — a choice can contain a comma (insert markup always does), so the
      # values are joined with a separator that cannot appear in OSCAL prose.
      value = ParameterValueList.join(selected)
      unless upsert_parameter_field(select_id, value)
        validation_errors << {
          select_id: select_id,
          error: "Selection is not attached to any control in this profile; nothing was written"
        }
        next
      end
      selections_updated += 1

      # #942 — a chosen branch can carry its own parameter ("establish
      # {{ insert: param, ac-20_odp.02 }}" is answered by odp.02). Accepting the
      # selection while that parameter is still blank stores a half-answered
      # question that reads as complete, and the gap only surfaces once the
      # resolved baseline is generated. Reported, not refused: the operator may
      # be supplying the two in either order, or in separate calls.
      unanswered_references(select_id, Array(selected)).each do |missing|
        validation_errors << {
          select_id: select_id,
          param_id: missing,
          error: "Selected choice references parameter #{missing}, which has no value"
        }
      end
    end

    {
      status: validation_errors.empty? ? "updated" : "partial",
      baseline_id: profile.slug,
      parameters_updated: params_updated,
      selections_updated: selections_updated,
      validation_errors: validation_errors
    }
  end

  # Exports the parameter schema in the requested format.
  #
  # @param format [Symbol] :json, :yaml, or :xml
  # @return [String] serialized schema
  def export(format: :json)
    schema = extract_schema

    case format.to_sym
    when :json
      JSON.pretty_generate(schema)
    when :yaml
      schema.deep_stringify_keys.to_yaml
    when :xml
      schema_to_xml(schema)
    else
      raise ArgumentError, "Unsupported format: #{format}. Use :json, :yaml, or :xml"
    end
  end

  private

  # Extracts raw OSCAL parameter definitions from catalog controls or resolved JSON.
  def extract_raw_parameters(family: nil)
    if profile.resolved_catalog_json.present? && profile.resolved_catalog_json != {}
      extract_from_resolved_catalog(family: family)
    elsif profile.control_catalog.present?
      extract_from_catalog_controls(family: family)
    else
      []
    end
  end

  # Extracts parameters from the resolved_catalog_json JSONB column.
  #
  # #999 — through ResolvedCatalog. This method already reached ONE level of
  # nesting by hand, which was enough for the enhancements NIST nests directly
  # under a control and silently wrong for anything deeper.
  def extract_from_resolved_catalog(family: nil)
    params = []

    ResolvedCatalog.wrap(profile.resolved_catalog_json).each_control do |control, group|
      next if family.present? && group["id"].to_s.upcase != family.upcase

      collect_control_params(control, params)
    end

    params
  end

  # Collects params from a single OSCAL control hash.
  def collect_control_params(control, params)
    (control["params"] || []).each do |param|
      params << param.merge(
        "_control_id" => control["id"],
        "_control_title" => control["title"],
        # A resolved catalog carries each parameter under the control that
        # declares it, so every row here is an owner.
        "_owns_param" => true
      )
    end
  end

  # Extracts parameters from associated CatalogControl records.
  def extract_from_catalog_controls(family: nil)
    params = []
    scope = profile.control_catalog.catalog_controls
      .joins(:control_family)
      .includes(:control_family)

    scope = scope.where(control_families: { code: family.upcase }) if family.present?

    scope.find_each do |catalog_control|
      # #1007 — `effective_params_list` returns a statement sub-part's PARENT
      # parameters when the sub-part's title cites them, so the same param_id
      # legitimately appears on several rows for display. Only one of those
      # controls declares it, and that is the one a value is stored against.
      own_param_ids = catalog_control.params_list.map { |p| p["id"] }.to_set

      catalog_control.effective_params_list.each do |param|
        params << param.merge(
          "_control_id" => catalog_control.control_id,
          "_control_title" => catalog_control.title,
          "_owns_param" => own_param_ids.include?(param["id"])
        )
      end
    end

    params
  end

  # Loads current parameter values from profile_control_fields.
  # #1007 — a parameter has ONE value per profile, and while the profile is a
  # draft the LAST UPDATE WINS, whether it arrived through the API or the UI.
  #
  # This used to walk `profile_controls` and assign into a flat `param_id =>
  # value` map, so where two controls held a row for the same parameter — a
  # control and a statement sub-part citing it — whichever the association
  # happened to yield last silently won. A tailored value could be written,
  # persisted, and then read back as the old one, with the write reporting
  # success. Ordering by `updated_at` makes the winner the most recent write
  # rather than an artefact of iteration order, and `upsert_parameter_field`
  # now collapses duplicates so there is normally only one row to choose from.
  def load_current_values
    ProfileControlField
      .joins(:profile_control)
      .where(profile_controls: { profile_document_id: profile.id })
      .where("field_name LIKE ?", "parameter:%")
      .order(:updated_at, :id)
      .pluck(:field_name, :field_value)
      .each_with_object({}) do |(field_name, field_value), values|
        values[field_name.delete_prefix("parameter:")] = field_value
      end
  end

  # Builds a parameter entry for the schema.
  def build_parameter(param, control_id, control_title, current_values)
    param_id = param["id"]
    constraint = extract_constraint(param)

    {
      param_id: param_id,
      control_id: control_id,
      control_title: control_title,
      label: param["label"],
      description: extract_description(param),
      type: infer_type(param),
      constraint: constraint,
      current_value: current_values[param_id],
      value: current_values[param_id] || ""
    }
  end

  # Builds a selection/enumeration entry for the schema.
  #
  # #942 — a choice may be composed from OTHER parameters rather than being a
  # literal value ("establish {{ insert: param, ac-20_odp.02 }}"). `choices`
  # keeps the verbatim OSCAL text, because that is what has to be written back
  # for the document to round-trip; `choice_details` carries the resolved
  # display form and the ids it depends on, so a consumer can render the term
  # instead of the markup and ask for the referenced parameter only when the
  # branch that needs it is chosen.
  def build_selection(param, control_id, control_title, current_values, resolver = nil)
    param_id = param["id"]
    select = param["select"] || {}
    choices = select["choice"] || []
    how_many = select["how-many"] || "one-or-more"

    current = current_values[param_id]
    selected = ParameterValueList.split(current)

    details = choices.map { |choice| build_choice(choice, resolver) }

    {
      select_id: param_id,
      control_id: control_id,
      control_title: control_title,
      label: param["label"],
      description: extract_description(param),
      how_many: how_many,
      choices: choices,
      choice_details: details,
      # The union across every choice — what this selection could require,
      # regardless of which branch is taken.
      depends_on: details.flat_map { |detail| detail[:references] }.uniq,
      selected: selected
    }
  end

  # One choice, in all three forms a consumer needs: what OSCAL stores, what a
  # person should read, and what it depends on.
  def build_choice(choice, resolver)
    {
      text: choice,
      display: resolver ? resolver.resolve_text(choice).strip : choice,
      references: OscalParamReference.ids(choice)
    }
  end

  # Parameter ids the SELECTED choices reference but which still hold no value.
  #
  # Only the chosen branches are examined: a selection's other choices may
  # reference parameters that are legitimately irrelevant, and demanding those
  # is the over-collection #942 exists to stop.
  #
  # Values are re-read rather than taken from the payload's own parameter list,
  # so a call that sets odp.02 and odp.01 together is satisfied by the write
  # that has already happened in this same pass.
  def unanswered_references(select_id, selected)
    return [] if selected.empty?

    choices = choices_for(select_id)
    return [] if choices.empty?

    chosen = choices.select { |choice| selected.include?(choice) }
    referenced = chosen.flat_map { |choice| OscalParamReference.ids(choice) }.uniq
    return [] if referenced.empty?

    values = load_current_values
    referenced.reject { |id| values[id].present? }
  end

  def choices_for(select_id)
    param = extract_raw_parameters.find { |p| p["id"] == select_id }
    Array(param&.dig("select", "choice"))
  end

  # param_id => label, across the whole profile.
  def parameter_labels
    extract_raw_parameters.each_with_object({}) do |param, labels|
      id = param["id"]
      labels[id] = param["label"] if id.present? && param["label"].present?
    end
  end

  # Finds or creates a ProfileControlField for the given parameter.
  # Returns true when a value was written, false when the parameter resolved to
  # no control in this profile. The caller counts the trues: #1007 shipped a
  # counter that incremented after this method had already returned early, so
  # `parameters_updated` counted ATTEMPTS and could not report the difference
  # even in principle.
  def upsert_parameter_field(param_id, value)
    control_id = find_control_id_for_param(param_id)
    return false unless control_id

    profile_control = profile.profile_controls.find_by(control_id: control_id)
    unless profile_control
      profile_control = profile.profile_controls.create!(
        control_id: control_id,
        title: control_id.upcase
      )
    end

    field = profile_control.profile_control_fields.find_or_initialize_by(
      field_name: "parameter:#{param_id}"
    )
    field.field_value = value
    field.save!

    # #1007 — a param_id is unique within a profile. Any row left on another
    # control is a duplicate of the same logical ODP and would shadow this
    # write on the next read.
    ProfileControlField
      .joins(:profile_control)
      .where(profile_controls: { profile_document_id: profile.id },
             field_name: "parameter:#{param_id}")
      .where.not(id: field.id)
      .delete_all

    true
  end

  # Which control a parameter is stored against.
  #
  # #1007 — prefer the control that DECLARES the parameter over one that merely
  # cites it in a statement sub-part. Both appear in the extracted list, and
  # taking whichever came first made the storage location depend on catalog
  # iteration order.
  def find_control_id_for_param(param_id)
    matches = extract_raw_parameters.select { |p| p["id"] == param_id }
    return nil if matches.empty?

    owner = matches.find { |p| p["_owns_param"] }
    (owner || matches.first)["_control_id"]
  end

  # Extracts constraint text from a parameter definition.
  def extract_constraint(param)
    constraints = param["constraints"] || []
    return nil if constraints.empty?
    constraints.map { |c| c["description"] || c["test"] }.compact.join("; ")
  end

  # Extracts description from guidelines or label.
  def extract_description(param)
    guidelines = param["guidelines"] || []
    if guidelines.any?
      guidelines.map { |g| g["prose"] }.compact.join(" ")
    else
      param["label"]
    end
  end

  # Infers parameter type from constraints and label.
  def infer_type(param)
    label = (param["label"] || "").downcase
    constraints = (param["constraints"] || []).map { |c| (c["description"] || "").downcase }

    if constraints.any? { |c| c.include?("integer") || c.include?("number") }
      "integer"
    elsif label.include?("time") || label.include?("period") || label.include?("duration")
      "duration"
    else
      "text"
    end
  end

  # Converts schema hash to XML string.
  def schema_to_xml(schema)
    builder = Builder::XmlMarkup.new(indent: 2)
    builder.instruct! :xml, version: "1.0", encoding: "UTF-8"
    builder.tag!("baseline-parameters",
      baseline: schema[:baseline],
      "baseline-level": schema[:baseline_level],
      version: schema[:version]) do
      builder.parameters do
        schema[:parameters].each do |param|
          builder.parameter(
            "param-id": param[:param_id],
            "control-id": param[:control_id],
            type: param[:type]
          ) do
            builder.label(param[:label]) if param[:label]
            builder.description(param[:description]) if param[:description]
            builder.constraint(param[:constraint]) if param[:constraint]
            builder.tag!("current-value", param[:current_value]) if param[:current_value]
            builder.value(param[:value])
          end
        end
      end
      builder.selections do
        schema[:selections].each do |sel|
          builder.selection(
            "select-id": sel[:select_id],
            "control-id": sel[:control_id],
            "how-many": sel[:how_many]
          ) do
            builder.label(sel[:label]) if sel[:label]
            builder.description(sel[:description]) if sel[:description]
            # #942 — the choice carries its resolved display form and the
            # parameters it references as attributes, so the XML says what the
            # JSON says. The element text stays the verbatim OSCAL so the file
            # round-trips.
            Array(sel[:choice_details]).each do |detail|
              attrs = { display: detail[:display] }
              attrs[:references] = detail[:references].join(" ") if detail[:references].present?
              builder.choice(detail[:text], **attrs)
            end
            sel[:selected].each { |s| builder.selected(s) }
          end
        end
      end
    end
  end
end
