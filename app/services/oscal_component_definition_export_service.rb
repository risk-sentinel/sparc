# Builds an OSCAL v1.1.2 Component Definition JSON document from a
# CdefDocument and its controls.  Validates the output against the
# official NIST JSON schema before returning.
#
# Usage:
#   service = OscalComponentDefinitionExportService.new(cdef_document)
#   json_string = service.export            # validates, raises on failure
#   json_string = service.export_unvalidated # skips validation (legacy)
#   result      = service.validation_result  # inspect errors without raising
#
class OscalComponentDefinitionExportService
  DEFAULT_OSCAL_VERSION = OscalSchema::DEFAULT_VERSION
  OSCAL_VERSION = DEFAULT_OSCAL_VERSION # backward compat

  def initialize(cdef_document)
    @document = cdef_document
  end

  # Build, validate, and return pretty-printed OSCAL JSON.
  # Raises OscalValidationError if the output fails schema validation.
  def export
    data = build_component_definition
    OscalSchemaValidationService.validate!(:component_definition, data, version: effective_oscal_version)
    JSON.pretty_generate(data)
  end

  # Build and return OSCAL JSON without schema validation.
  def export_unvalidated
    JSON.pretty_generate(build_component_definition)
  end

  # Build the document and return the validation result (does not raise).
  def validation_result
    data = build_component_definition
    OscalSchemaValidationService.validate(:component_definition, data)
  end


  def effective_oscal_version
    @document.oscal_version.presence || DEFAULT_OSCAL_VERSION
  end

  private

  def build_component_definition
    {
      "component-definition" => {
        "uuid"         => @document.uuid,
        "metadata"     => build_metadata,
        "components"   => [ build_component ],
        "back-matter"  => build_back_matter
      }.compact
    }
  end

  def build_metadata
    @document.build_oscal_metadata(
      default_version: @document.cdef_version || "1.0.0",
      default_roles: [
        { "id" => "prepared-by", "title" => "Prepared By" }
      ],
      default_parties: [
        { "uuid" => OscalUuidService.org_party_uuid_for(@document),
          "type" => "organization", "name" => "SPARC Export" }
      ]
    )
  end

  def build_component
    controls = @document.cdef_controls
                        .order(:row_order)
                        .includes(:cdef_control_fields)

    {
      "uuid"        => OscalUuidService.derived(@document.uuid, "cdef-component"),
      "type"        => "software",
      "title"       => @document.name,
      "description" => @document.description || "Imported component definition",
      "control-implementations" => [ build_control_implementation(controls) ]
    }
  end

  def build_control_implementation(controls)
    {
      "uuid"        => OscalUuidService.derived(@document.uuid, "cdef-control-implementation"),
      "source"      => determine_source,
      "description" => "Controls from #{@document.cdef_type || 'imported'} component definition: #{@document.name}",
      "implemented-requirements" => controls.map { |ctrl| build_implemented_requirement(ctrl) }
    }
  end

  def build_implemented_requirement(control)
    field_map = control.cdef_control_fields.index_by(&:field_name)

    result = {
      "uuid"        => OscalUuidService.derived(control.uuid, "cdef-ir"),
      "control-id"  => normalize_control_id(control, field_map),
      "description" => build_description(control, field_map)
    }

    props = build_props(control)
    result["props"] = props if props.any?

    stmts = build_ir_statements(control, field_map, result["control-id"])
    result["statements"] = stmts if stmts

    # OSCAL-compliant enhanced fields
    append_ir_enhanced_props(result, field_map)
    append_ir_responsible_roles(result, field_map)
    append_ir_set_parameters(result, field_map)
    append_ir_links(result, control)

    result
  end

  # #393: table-driven statements when records exist (backfilled or imported);
  # falls back to a single field-synthesized statement for un-backfilled CDEFs
  # (no linked profile) so existing exports work. Returns the array or nil.
  def build_ir_statements(control, field_map, control_id)
    if control.cdef_control_statements.any?
      return control.cdef_control_statements.order(:row_order).map do |stmt|
        entry = {
          "statement-id" => stmt.statement_id,
          "uuid"         => stmt.uuid,
          "description"  => stmt.implementation_prose.presence || stmt.remarks
        }
        entry["set-parameters"] = stmt.set_parameters_data if stmt.set_parameters_data.present?
        entry.compact
      end
    end

    narrative = field_map["implementation_narrative"]&.field_value
    return nil if narrative.blank?

    [ {
      "statement-id" => "#{control_id}_stmt",
      "uuid"         => OscalUuidService.derived(control.uuid, "cdef-statement", "default"),
      "description"  => narrative
    } ]
  end

  # Append CDEF field-derived props in a stable order (implementation-status,
  # control-origin, baseline-priority).
  def append_ir_enhanced_props(result, field_map)
    {
      "implementation_status" => "implementation-status",
      "control_origin"        => "control-origin",
      "baseline_priority"     => "baseline-priority"
    }.each do |field_name, prop_name|
      value = field_map[field_name]&.field_value
      next if value.blank?
      result["props"] ||= []
      result["props"] << { "name" => prop_name, "value" => value }
    end
  end

  def append_ir_responsible_roles(result, field_map)
    roles = field_map["responsible_roles"]&.field_value
    return if roles.blank?
    result["responsible-roles"] = roles.split(",").map(&:strip).reject(&:blank?).map do |role|
      { "role-id" => role }
    end
  end

  def append_ir_set_parameters(result, field_map)
    params = field_map["set_parameters"]&.field_value
    return if params.blank?
    parsed = JSON.parse(params)
    result["set-parameters"] = parsed.map do |param|
      { "param-id" => param["id"] || param["param-id"], "values" => Array(param["value"] || param["values"]) }
    end
  rescue JSON::ParserError
    # Skip malformed set_parameters
  end

  def append_ir_links(result, control)
    return unless control.respond_to?(:back_matter_resources) && control.back_matter_resources.any?
    result["links"] = control.back_matter_resources.map do |resource|
      { "href" => "##{resource.uuid}", "rel" => resource.rel.presence || "reference" }
    end
  end

  def normalize_control_id(control, field_map)
    raw = if (nist = field_map["nist_controls"]&.field_value).present?
      nist.split(",").first.strip
    elsif control.control_id.present?
      control.control_id
    else
      "unknown-#{control.id}"
    end

    # OSCAL TokenDatatype: ^(\p{L}|_)(\p{L}|\p{N}|[.\-_])*$
    # Convert parenthesised enhancements to dot notation: "SI-2 (2)" → "si-2.2"
    raw.downcase
       .gsub(/\s+/, "-")       # spaces → hyphens
       .gsub("(", ".")         # open paren → dot (enhancement separator)
       .gsub(")", "")          # strip close paren
       .gsub(/\.{2,}/, ".")    # collapse multiple dots
       .gsub(/-\./, ".")       # "si-2.2" not "si-2-.2"
  end

  def build_description(control, field_map)
    parts = []
    parts << control.title if control.title.present?
    parts << field_map["description"]&.field_value if field_map["description"]&.field_value.present?
    parts << "Fix: #{field_map['fix_text']&.field_value}" if field_map["fix_text"]&.field_value.present?
    parts.join("\n\n").presence || "No description available"
  end

  def build_props(control)
    props = []
    props << { "name" => "severity", "value" => control.severity } if control.severity.present?
    props << { "name" => "rule-id",  "value" => control.rule_id }  if control.rule_id.present?
    props << { "name" => "group-id", "value" => control.group_id } if control.group_id.present?
    props << { "name" => "stig-id",  "value" => control.stig_id }  if control.stig_id.present?

    if control.cci_references.present?
      control.cci_references.split(",").each do |cci|
        props << { "name" => "cci", "ns" => "http://cyber.mil/cci", "value" => cci.strip }
      end
    end

    props
  end

  def determine_source
    case @document.cdef_type
    when "disa_stig" then "https://public.cyber.mil/stigs/"
    when "cis"       then "https://www.cisecurity.org/cis-benchmarks"
    when "scap"      then "https://csrc.nist.gov/projects/security-content-automation-protocol"
    else "https://sparc.local/component-definitions/#{@document.id}"
    end
  end

  def build_back_matter
    @document.build_oscal_back_matter
  end
end
