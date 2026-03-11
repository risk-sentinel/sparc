# Parses an OSCAL Profile YAML file by converting to a temporary JSON file
# and delegating to ProfileJsonParserService#parse.
#
# ProfileJsonParserService does not expose a parse_from_hash method, so we
# write the parsed YAML data to a temporary JSON file for delegation.
#
class ProfileYamlParserService
  def initialize(document, file_path)
    @document  = document
    @file_path = file_path
  end

  def parse
    content = File.read(@file_path).force_encoding("UTF-8")
    data = YAML.safe_load(content, permitted_classes: [ Date, Time ])

    tmp_json = Tempfile.new([ "profile_yaml_", ".json" ])
    tmp_json.write(JSON.generate(data))
    tmp_json.close

    ProfileJsonParserService.new(@document, tmp_json.path).parse
  ensure
    tmp_json&.unlink
  end
end
