# Parses an OSCAL Component Definition YAML file by converting to a temporary
# JSON file and delegating to CdefJsonParserService#parse.
#
# CdefJsonParserService auto-detects format (OSCAL CDEF, InSpec, STIG Viewer,
# generic) so the same multi-format support is available for YAML inputs.
#
class CdefYamlParserService
  include ProgressTrackable

  def initialize(document, file_path)
    @document  = document
    @file_path = file_path
  end

  def parse(validate: true)
    update_processing_stage!(:reading_file)
    content = File.read(@file_path).force_encoding("UTF-8")
    data = YAML.safe_load(content, permitted_classes: [ Date, Time ])

    update_processing_stage!(:creating_records)
    tmp_json = Tempfile.new([ "cdef_yaml_", ".json" ])
    tmp_json.write(JSON.generate(data))
    tmp_json.close

    CdefJsonParserService.new(@document, tmp_json.path).parse(validate: validate)
  ensure
    tmp_json&.unlink
  end
end
