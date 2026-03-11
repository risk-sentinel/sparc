# Parses an OSCAL POA&M YAML file by loading the YAML to a Ruby hash
# and delegating to PoamJsonParserService#parse_from_hash.
#
# Follows the same delegation pattern as PoamXmlParserService.
#
class PoamYamlParserService
  def initialize(document, file_path)
    @document  = document
    @file_path = file_path
  end

  def parse
    content = File.read(@file_path).force_encoding("UTF-8")
    data = YAML.safe_load(content, permitted_classes: [ Date, Time ])

    json_parser = PoamJsonParserService.new(@document, nil)
    json_parser.parse_from_hash(data)
  end
end
