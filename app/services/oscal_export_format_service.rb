# Converts OSCAL export data between formats (JSON → YAML, JSON → XML).
#
# This is a thin wrapper around existing export services. The flow is:
#   1. An export service (e.g., OscalSspExportService) builds and validates JSON
#   2. This service converts the JSON output to the desired format
#
# Usage:
#   json_string = OscalSspExportService.new(ssp_document).export
#   yaml_output = OscalExportFormatService.to_yaml(json_string)
#   xml_output  = OscalExportFormatService.to_xml(json_string, :ssp)
#
class OscalExportFormatService
  # Convert a JSON string to YAML.
  #
  # @param json_string [String] valid OSCAL JSON
  # @return [String] YAML representation
  def self.to_yaml(json_string)
    data = JSON.parse(json_string)
    data.to_yaml
  end

  # Convert a JSON string to OSCAL-namespaced XML.
  #
  # @param json_string [String] valid OSCAL JSON
  # @param model_type [Symbol] OSCAL model type (e.g., :ssp, :component_definition)
  # @return [String] XML string with OSCAL namespace
  def self.to_xml(json_string, model_type)
    data = JSON.parse(json_string)
    OscalJsonToXmlConverter.new(model_type, data).convert
  end
end
