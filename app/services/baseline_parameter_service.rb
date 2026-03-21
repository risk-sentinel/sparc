# frozen_string_literal: true

require "builder"

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

    parameters = []
    selections = []

    raw_params.each do |param|
      param_id = param["id"]
      control_id = param["_control_id"]
      control_title = param["_control_title"]

      if param["select"].present?
        selections << build_selection(param, control_id, control_title, current_values)
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

      upsert_parameter_field(param_id, value.to_s)
      params_updated += 1
    end

    # Update selections
    (payload[:selections] || payload["selections"] || []).each do |sel_entry|
      select_id = sel_entry[:select_id] || sel_entry["select_id"]
      selected = sel_entry[:selected] || sel_entry["selected"] || []

      unless known_param_ids.include?(select_id)
        validation_errors << { select_id: select_id, error: "Unknown selection ID" }
        next
      end

      value = selected.is_a?(Array) ? selected.join(", ") : selected.to_s
      upsert_parameter_field(select_id, value)
      selections_updated += 1
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
      require "yaml"
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
  def extract_from_resolved_catalog(family: nil)
    catalog = profile.resolved_catalog_json
    params = []

    groups = catalog["groups"] || catalog.dig("catalog", "groups") || []
    groups.each do |group|
      group_id = group["id"].to_s.upcase # e.g., "ac"
      next if family.present? && group_id != family.upcase

      (group["controls"] || []).each do |control|
        collect_control_params(control, params)
        # Include enhancement params
        (control["controls"] || []).each do |enhancement|
          collect_control_params(enhancement, params)
        end
      end
    end

    params
  end

  # Collects params from a single OSCAL control hash.
  def collect_control_params(control, params)
    (control["params"] || []).each do |param|
      params << param.merge(
        "_control_id" => control["id"],
        "_control_title" => control["title"]
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
      catalog_control.effective_params_list.each do |param|
        params << param.merge(
          "_control_id" => catalog_control.control_id,
          "_control_title" => catalog_control.title
        )
      end
    end

    params
  end

  # Loads current parameter values from profile_control_fields.
  def load_current_values
    values = {}
    profile.profile_controls.includes(:profile_control_fields).each do |pc|
      pc.profile_control_fields.each do |field|
        if field.field_name.start_with?("parameter:") && !field.field_name.start_with?("parameter_label:")
          param_id = field.field_name.delete_prefix("parameter:")
          values[param_id] = field.field_value
        end
      end
    end
    values
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
  def build_selection(param, control_id, control_title, current_values)
    param_id = param["id"]
    select = param["select"] || {}
    choices = select["choice"] || []
    how_many = select["how-many"] || "one-or-more"

    current = current_values[param_id]
    selected = current.present? ? current.split(/\s*,\s*/) : []

    {
      select_id: param_id,
      control_id: control_id,
      control_title: control_title,
      label: param["label"],
      description: extract_description(param),
      how_many: how_many,
      choices: choices,
      selected: selected
    }
  end

  # Finds or creates a ProfileControlField for the given parameter.
  def upsert_parameter_field(param_id, value)
    # Find the profile_control this parameter belongs to
    control_id = find_control_id_for_param(param_id)
    return unless control_id

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
  end

  # Looks up which control_id a parameter belongs to.
  def find_control_id_for_param(param_id)
    extract_raw_parameters.find { |p| p["id"] == param_id }&.dig("_control_id")
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
            sel[:choices].each { |c| builder.choice(c) }
            sel[:selected].each { |s| builder.selected(s) }
          end
        end
      end
    end
  end
end
