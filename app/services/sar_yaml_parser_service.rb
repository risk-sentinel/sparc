# Parses an OSCAL Assessment Results YAML file by loading the YAML to a Ruby
# hash and delegating to SarJsonParserService#parse_from_hash.
#
# Follows the same delegation pattern as SarXmlParserService.
#
class SarYamlParserService
  include ProgressTrackable

  def initialize(document, file_path)
    @document  = document
    @file_path = file_path
  end

  def parse
    update_processing_stage!(:reading_file)
    content = File.read(@file_path).force_encoding("UTF-8")
    data = YAML.safe_load(content, permitted_classes: [ Date, Time ])

    update_processing_stage!(:creating_records)
    json_parser = SarJsonParserService.new(@document, nil)
    json_parser.parse_from_hash(data)
  end
end
