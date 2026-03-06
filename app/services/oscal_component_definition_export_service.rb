class OscalComponentDefinitionExportService
  OSCAL_VERSION = "1.1.2"

  def initialize(cdef_document)
    @document = cdef_document
  end

  def export
    JSON.pretty_generate(build_component_definition)
  end

  private

  def build_component_definition
    {
      "component-definition" => {
        "uuid"       => SecureRandom.uuid,
        "metadata"   => build_metadata,
        "components" => [ build_component ]
      }
    }
  end

  def build_metadata
    {
      "title"         => @document.name,
      "version"       => @document.cdef_version || "1.0.0",
      "oscal-version" => OSCAL_VERSION,
      "last-modified" => Time.current.iso8601,
      "roles" => [
        { "id" => "prepared-by", "title" => "Prepared By" }
      ],
      "parties" => [
        {
          "uuid" => SecureRandom.uuid,
          "type" => "organization",
          "name" => "SPARC Export"
        }
      ]
    }
  end

  def build_component
    controls = @document.cdef_controls
                        .order(:row_order)
                        .includes(:cdef_control_fields)

    {
      "uuid"        => SecureRandom.uuid,
      "type"        => "software",
      "title"       => @document.name,
      "description" => @document.description || "Imported component definition",
      "control-implementations" => [ build_control_implementation(controls) ]
    }
  end

  def build_control_implementation(controls)
    {
      "uuid"        => SecureRandom.uuid,
      "source"      => determine_source,
      "description" => "Controls from #{@document.cdef_type || 'imported'} component definition: #{@document.name}",
      "implemented-requirements" => controls.map { |ctrl| build_implemented_requirement(ctrl) }
    }
  end

  def build_implemented_requirement(control)
    field_map = control.cdef_control_fields.index_by(&:field_name)

    result = {
      "uuid"        => SecureRandom.uuid,
      "control-id"  => normalize_control_id(control, field_map),
      "description" => build_description(control, field_map)
    }

    props = build_props(control)
    result["props"] = props if props.any?

    narrative = field_map["implementation_narrative"]&.field_value
    if narrative.present?
      result["statements"] = [ {
        "statement-id" => "#{result['control-id']}_stmt",
        "uuid"         => SecureRandom.uuid,
        "description"  => narrative
      } ]
    end

    result
  end

  def normalize_control_id(control, field_map)
    nist = field_map["nist_controls"]&.field_value
    if nist.present?
      nist.split(",").first.strip.downcase.gsub(/\s+/, "-")
    elsif control.control_id.present?
      control.control_id.downcase.gsub(/\s+/, "-")
    else
      "unknown-#{control.id}"
    end
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
end
